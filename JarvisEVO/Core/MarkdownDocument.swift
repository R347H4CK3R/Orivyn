import Foundation

/// Deliberately bounded Markdown subset for chat, not a full CommonMark implementation.
/// HTML remains text. Reference links, footnotes and indented code are not interpreted.
/// Positions are source-line identities so appending a stream does not recreate earlier blocks.
enum MarkdownRenderingLimits {
    static let sourceBytes = 500_000
    static let sourceLines = 20_000
    static let blocks = 256
    static let listItems = 256
    static let nesting = 16
    static let tableColumns = 32
    static let tableRows = 128
    static let totalTableRows = 256
    static let tableCells = 2_048
    static let mathBlocks = 16
}

enum MarkdownFallbackReason: Error, Equatable, Sendable {
    case sourceBytes, sourceLines, blocks, listItems, nesting
    case tableColumns, tableRows, totalTableRows, tableCells, mathBlocks

    var explanation: String {
        switch self {
        case .sourceBytes: "This response is too large for formatted display."
        case .sourceLines: "This response has too many lines for formatted display."
        case .blocks: "This response has too many formatted sections."
        case .listItems: "This response has too many list items."
        case .nesting: "This response has too many nested sections."
        case .tableColumns: "A table has too many columns for formatted display."
        case .tableRows: "A table has too many rows for formatted display."
        case .totalTableRows: "This response has too many table rows overall."
        case .tableCells: "This response has too many table cells."
        case .mathBlocks: "This response has too many equations for formatted display."
        }
    }
}

struct MarkdownDocument: Equatable, Sendable {
    let blocks: [MarkdownBlock]

    init(source: String) {
        guard source.utf8.count <= MarkdownRenderingLimits.sourceBytes else {
            blocks = [.init(id: 0, kind: .plainSource(source: source, reason: .sourceBytes))]
            return
        }
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        // Check before allocating an array with one String per line.
        var lineCount = 1
        for byte in normalized.utf8 where byte == 10 {
            lineCount += 1
            if lineCount > MarkdownRenderingLimits.sourceLines {
                blocks = [.init(id: 0, kind: .plainSource(source: source, reason: .sourceLines))]
                return
            }
        }
        do {
            blocks = try MarkdownBlockParser(lines: normalized.components(separatedBy: "\n"), budget: MarkdownParsingBudget()).parse()
        } catch let reason as MarkdownFallbackReason {
            // Keep original, pre-normalization source, not a rendered or truncated prefix.
            blocks = [.init(id: 0, kind: .plainSource(source: source, reason: reason))]
        } catch {
            blocks = [.init(id: 0, kind: .plainSource(source: source, reason: .blocks))]
        }
    }
}

/// Shared by all recursive branches; limits are checked before appending nodes/cells.
private final class MarkdownParsingBudget {
    private var blocks = 0
    private var listItems = 0
    private var tableRows = 0
    private var tableCells = 0
    private var mathBlocks = 0

    func reserveBlock() throws {
        guard blocks < MarkdownRenderingLimits.blocks else { throw MarkdownFallbackReason.blocks }
        blocks += 1
    }

    func reserveListItem() throws {
        guard listItems < MarkdownRenderingLimits.listItems else { throw MarkdownFallbackReason.listItems }
        listItems += 1
    }

    func reserveMathBlock() throws {
        guard mathBlocks < MarkdownRenderingLimits.mathBlocks else { throw MarkdownFallbackReason.mathBlocks }
        mathBlocks += 1
    }

    func reserveTableHeader(columns: Int) throws {
        guard columns <= MarkdownRenderingLimits.tableColumns else { throw MarkdownFallbackReason.tableColumns }
        try reserveCells(columns)
    }

    func reserveTableRow(columns: Int, rowsInTable: Int) throws {
        guard rowsInTable < MarkdownRenderingLimits.tableRows else { throw MarkdownFallbackReason.tableRows }
        guard tableRows < MarkdownRenderingLimits.totalTableRows else { throw MarkdownFallbackReason.totalTableRows }
        try reserveCells(columns)
        tableRows += 1
    }

    private func reserveCells(_ count: Int) throws {
        guard count <= MarkdownRenderingLimits.tableCells - tableCells else { throw MarkdownFallbackReason.tableCells }
        tableCells += count
    }
}

struct MarkdownBlock: Equatable, Sendable, Identifiable {
    let id: Int
    let kind: Kind

    indirect enum Kind: Equatable, Sendable {
        case paragraph(String)
        case plainSource(source: String, reason: MarkdownFallbackReason)
        case heading(level: Int, text: String)
        case list(ordered: Bool, items: [MarkdownListItem])
        case quote([MarkdownBlock])
        case code(MarkdownCodeBlock)
        case table(MarkdownTable)
        case thematicBreak
        case math(MarkdownMathBlock)
    }
}

struct MarkdownListItem: Equatable, Sendable, Identifiable {
    let id: Int
    let number: Int?
    let isChecked: Bool?
    let blocks: [MarkdownBlock]
}

struct MarkdownCodeBlock: Equatable, Sendable {
    let language: String
    let text: String
    let isClosed: Bool
}

struct MarkdownMathBlock: Equatable, Hashable, Sendable {
    let source: String
    let isClosed: Bool
}

struct MarkdownTable: Equatable, Sendable {
    enum Alignment: Equatable, Sendable { case leading, center, trailing }
    let headers: [String]
    let alignments: [Alignment]
    let rows: [[String]]
}

private struct MarkdownBlockParser {
    let lines: [String]
    var depth = 0
    let budget: MarkdownParsingBudget

    func parse() throws -> [MarkdownBlock] {
        guard depth <= MarkdownRenderingLimits.nesting else { throw MarkdownFallbackReason.nesting }
        var blocks: [MarkdownBlock] = []
        var index = 0
        while index < lines.count {
            let start = index
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { index += 1; continue }
            try budget.reserveBlock()
            if let opening = fence(line) {
                index += 1
                var content: [String] = []
                while index < lines.count, !closesFence(lines[index], opening) {
                    content.append(removingIndent(lines[index], atMost: opening.indent))
                    index += 1
                }
                let closed = index < lines.count
                if closed { index += 1 }
                let value = content.joined(separator: "\n") + (closed && !content.isEmpty ? "\n" : "")
                blocks.append(.init(id: start, kind: .code(.init(language: opening.language, text: value, isClosed: closed))))
                continue
            }
            if let math = mathOpening(line) {
                try budget.reserveMathBlock()
                if let source = math.complete {
                    blocks.append(.init(id: start, kind: .math(.init(source: source, isClosed: true))))
                    index += 1
                } else {
                    index += 1
                    var content = math.firstLine.isEmpty ? [] : [math.firstLine]
                    while index < lines.count, trimmed(lines[index]) != math.closer {
                        content.append(lines[index]); index += 1
                    }
                    let closed = index < lines.count
                    if closed { index += 1 }
                    blocks.append(.init(id: start, kind: .math(.init(source: content.joined(separator: "\n"), isClosed: closed))))
                }
                continue
            }
            if let heading = heading(line) {
                blocks.append(.init(id: start, kind: .heading(level: heading.level, text: heading.text)))
                index += 1; continue
            }
            if isThematicBreak(line) {
                blocks.append(.init(id: start, kind: .thematicBreak)); index += 1; continue
            }
            if let quoted = quote(line) {
                var content = [quoted]
                index += 1
                while index < lines.count, let next = quote(lines[index]) { content.append(next); index += 1 }
                blocks.append(.init(id: start, kind: .quote(try MarkdownBlockParser(lines: content, depth: depth + 1, budget: budget).parse())))
                continue
            }
            if let first = listMarker(line) {
                var items: [MarkdownListItem] = []
                while index < lines.count, let marker = listMarker(lines[index]), marker.indent == first.indent, marker.ordered == first.ordered {
                    try budget.reserveListItem()
                    let itemStart = index
                    var content = [marker.text]
                    index += 1
                    while index < lines.count {
                        let next = lines[index]
                        if let nextMarker = listMarker(next), nextMarker.indent <= first.indent { break }
                        if trimmed(next).isEmpty {
                            // A blank belongs to this item only when followed by an indented continuation.
                            if index + 1 < lines.count, indentation(lines[index + 1]) >= marker.contentIndent {
                                content.append(""); index += 1; continue
                            }
                            break
                        }
                        guard indentation(next) >= marker.contentIndent else { break }
                        content.append(removingIndent(next, atMost: marker.contentIndent)); index += 1
                    }
                    var checked: Bool?
                    if let firstLine = content.first, firstLine.hasPrefix("[ ] ") || firstLine.hasPrefix("[x] ") || firstLine.hasPrefix("[X] ") {
                        checked = !firstLine.hasPrefix("[ ] ")
                        content[0] = String(firstLine.dropFirst(4))
                    }
                    items.append(.init(id: itemStart, number: marker.number, isChecked: checked,
                                       blocks: try MarkdownBlockParser(lines: content, depth: depth + 1, budget: budget).parse()))
                    if index < lines.count, trimmed(lines[index]).isEmpty,
                       index + 1 < lines.count, let next = listMarker(lines[index + 1]), next.indent == first.indent, next.ordered == first.ordered {
                        index += 1
                    }
                }
                blocks.append(.init(id: start, kind: .list(ordered: first.ordered, items: items)))
                continue
            }
            if let tableStart = tableOpening(at: index) {
                try budget.reserveTableHeader(columns: tableStart.headers.count)
                index += 2
                var rows: [[String]] = []
                while index < lines.count, lines[index].contains("|"), !trimmed(lines[index]).isEmpty {
                    var cells = tableCells(lines[index])
                    guard cells.count <= tableStart.headers.count else { break }
                    try budget.reserveTableRow(columns: tableStart.headers.count, rowsInTable: rows.count)
                    cells.append(contentsOf: repeatElement("", count: tableStart.headers.count - cells.count))
                    rows.append(cells); index += 1
                }
                blocks.append(.init(id: start, kind: .table(.init(headers: tableStart.headers, alignments: tableStart.alignments, rows: rows))))
                continue
            }
            if index + 1 < lines.count, let level = setextLevel(lines[index + 1]) {
                blocks.append(.init(id: start, kind: .heading(level: level, text: trimmed(line))))
                index += 2; continue
            }
            var paragraph = [line]
            index += 1
            while index < lines.count, !trimmed(lines[index]).isEmpty, !startsBlock(at: index) {
                paragraph.append(lines[index]); index += 1
            }
            blocks.append(.init(id: start, kind: .paragraph(paragraph.joined(separator: "\n"))))
        }
        return blocks
    }

    private func startsBlock(at index: Int) -> Bool {
        let line = lines[index]
        return fence(line) != nil || mathOpening(line) != nil || heading(line) != nil || quote(line) != nil ||
            listMarker(line) != nil || isThematicBreak(line) || tableOpening(at: index) != nil
    }

    private struct Fence { let marker: Character; let count: Int; let indent: Int; let language: String }
    private func fence(_ line: String) -> Fence? {
        let indent = indentation(line)
        guard indent <= 3 else { return nil }
        let text = line.dropFirst(indent)
        guard let first = text.first, first == "`" || first == "~" else { return nil }
        let count = text.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        let info = trimmed(String(text.dropFirst(count)))
        guard first != "`" || !info.contains("`") else { return nil }
        let language = String(info.split(whereSeparator: \.isWhitespace).first ?? "").lowercased()
        return .init(marker: first, count: count, indent: indent, language: String(language.prefix(40)))
    }

    private func closesFence(_ line: String, _ opening: Fence) -> Bool {
        let indent = indentation(line)
        guard indent <= 3 else { return false }
        let text = line.dropFirst(indent)
        let count = text.prefix(while: { $0 == opening.marker }).count
        return count >= opening.count && trimmed(String(text.dropFirst(count))).isEmpty
    }

    private func heading(_ line: String) -> (level: Int, text: String)? {
        guard indentation(line) <= 3 else { return nil }
        let text = line.dropFirst(indentation(line))
        let count = text.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count) else { return nil }
        let rest = text.dropFirst(count)
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        var value = trimmed(String(rest))
        let closingCount = value.reversed().prefix(while: { $0 == "#" }).count
        if closingCount > 0 {
            let before = value.dropLast(closingCount)
            if before.last?.isWhitespace == true || before.isEmpty { value = trimmed(String(before)) }
        }
        return (count, value)
    }

    private func setextLevel(_ line: String) -> Int? {
        guard indentation(line) <= 3 else { return nil }
        let value = trimmed(line)
        if !value.isEmpty, value.allSatisfy({ $0 == "=" }) { return 1 }
        if !value.isEmpty, value.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private func isThematicBreak(_ line: String) -> Bool {
        guard indentation(line) <= 3 else { return false }
        let value = line.filter { !$0.isWhitespace }
        guard value.count >= 3, let first = value.first, first == "-" || first == "*" || first == "_" else { return false }
        return value.allSatisfy { $0 == first }
    }

    private func quote(_ line: String) -> String? {
        guard indentation(line) <= 3 else { return nil }
        let text = line.dropFirst(indentation(line))
        guard text.first == ">" else { return nil }
        let rest = text.dropFirst()
        return String(rest.first == " " ? rest.dropFirst() : rest)
    }

    private struct ListMarker {
        let indent: Int; let contentIndent: Int; let number: Int?; let text: String
        var ordered: Bool { number != nil }
    }
    private func listMarker(_ line: String) -> ListMarker? {
        let indent = indentation(line)
        let text = line.dropFirst(indent)
        guard let first = text.first else { return nil }
        let markerLength: Int
        let number: Int?
        if first == "-" || first == "*" || first == "+" { markerLength = 1; number = nil }
        else {
            let digits = text.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, digits.count <= 9, let value = Int(digits) else { return nil }
            let after = text.dropFirst(digits.count)
            guard after.first == "." || after.first == ")" else { return nil }
            markerLength = digits.count + 1; number = value
        }
        let rest = text.dropFirst(markerLength)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        let spacing = min(4, rest.prefix(while: { $0 == " " }).count)
        let consumed = rest.first == "\t" ? 1 : max(rest.isEmpty ? 0 : 1, spacing)
        return .init(indent: indent, contentIndent: indent + markerLength + max(1, consumed), number: number,
                     text: String(rest.dropFirst(consumed)))
    }

    private func tableOpening(at index: Int) -> (headers: [String], alignments: [MarkdownTable.Alignment])? {
        guard index + 1 < lines.count, lines[index].contains("|") else { return nil }
        let headers = tableCells(lines[index])
        let delimiters = tableCells(lines[index + 1])
        guard !headers.isEmpty, headers.count == delimiters.count else { return nil }
        var alignments: [MarkdownTable.Alignment] = []
        for cell in delimiters {
            let raw = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard raw.count >= 3, raw.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(cell.hasSuffix(":") ? (cell.hasPrefix(":") ? .center : .trailing) : .leading)
        }
        return (headers, alignments)
    }

    /// Split unescaped pipes outside balanced ticks. One sentinel column bounds row allocation.
    private func tableCells(_ line: String) -> [String] {
        let characters = Array(trimmed(line))
        // Count runs up front, avoiding repeated suffix scans for malformed input.
        var remainingRuns: [Int: Int] = [:]
        var scan = 0
        while scan < characters.count {
            if characters[scan] == "\\", scan + 1 < characters.count { scan += 2; continue }
            if characters[scan] == "`" {
                var end = scan
                while end < characters.count, characters[end] == "`" { end += 1 }
                remainingRuns[end - scan, default: 0] += 1
                scan = end
            } else { scan += 1 }
        }
        var cells: [String] = []
        var cell = ""
        var index = characters.first == "|" ? 1 : 0
        var codeRun = 0
        while index < characters.count {
            let value = characters[index]
            if value == "\\", index + 1 < characters.count {
                if characters[index + 1] == "|" { cell.append("|"); index += 2; continue }
                if characters[index + 1] == "\\" || characters[index + 1] == "`" {
                    cell.append(value); cell.append(characters[index + 1]); index += 2; continue
                }
            }
            if value == "`" {
                var end = index
                while end < characters.count, characters[end] == "`" { end += 1 }
                let run = end - index
                remainingRuns[run, default: 0] -= 1
                if codeRun == run { codeRun = 0 }
                else if codeRun == 0, remainingRuns[run, default: 0] > 0 { codeRun = run }
                cell += String(repeating: "`", count: run); index = end; continue
            }
            if value == "|", codeRun == 0 {
                cells.append(trimmed(cell)); cell = ""
                if cells.count > MarkdownRenderingLimits.tableColumns { return cells }
            } else { cell.append(value) }
            index += 1
        }
        cells.append(trimmed(cell))
        if characters.last == "|", cells.last == "", cells.count > 1 { cells.removeLast() }
        return cells
    }

    private func mathOpening(_ line: String) -> (closer: String, firstLine: String, complete: String?)? {
        guard indentation(line) <= 3 else { return nil }
        let value = trimmed(line)
        let opener: String
        let closer: String
        if value.hasPrefix("$$") { opener = "$$"; closer = "$$" }
        else if value.hasPrefix("\\[") { opener = "\\["; closer = "\\]" }
        else { return nil }
        let rest = String(value.dropFirst(opener.count))
        if rest.hasSuffix(closer) { return (closer, "", String(rest.dropLast(closer.count))) }
        return (closer, rest, nil)
    }

    private func indentation(_ value: String) -> Int { value.prefix(while: { $0 == " " }).count }
    private func removingIndent(_ value: String, atMost count: Int) -> String { String(value.dropFirst(min(count, indentation(value)))) }
    private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespaces) }
}

/// Only ordinary web URLs may reach the explicit user-confirmation UI. No automatic opens.
enum MarkdownLinkPolicy {
    static func allowedURL(_ value: String) -> URL? {
        guard !value.isEmpty, !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let decoded = value.removingPercentEncoding,
              !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              let url = parts.url else { return nil }
        return url
    }
}

struct MarkdownCodeToken: Equatable, Sendable {
    enum Style: Equatable, Sendable { case plain, keyword, string, number, comment }
    let text: String
    let style: Style
}

/// Small lexical highlighter, not a compiler or executor. Unknown languages stay uncolored.
/// The original code is never rewritten, including incomplete strings and Unicode identifiers.
enum MarkdownSyntaxHighlighter {
    /// Each token becomes a native attributed-text run; byte bounds alone are insufficient.
    static let maximumTokens = 4_096
    static func tokens(_ source: String, language: String) -> [MarkdownCodeToken] {
        let language = language.lowercased()
        let python = ["python", "py"].contains(language)
        let shell = ["bash", "sh", "shell", "zsh"].contains(language)
        let json = ["json", "jsonc"].contains(language)
        let cFamily = ["swift", "javascript", "js", "typescript", "ts", "jsx", "tsx", "c", "cpp", "c++", "objective-c", "objc", "java", "kotlin", "rust", "go"].contains(language)
        guard (python || shell || json || cFamily), source.utf8.count <= 100_000 else { return [.init(text: source, style: .plain)] }
        let keywords = Set(("actor as async await break case catch class const continue default defer do else enum extension false final for func function guard if import in init interface internal is let nil null private protocol public repeat return self static struct super switch throw throws true try typealias var void where while yield " +
            "and assert def del elif except finally from global lambda None nonlocal not or pass raise True False with " +
            "auto bool char double float int long namespace new package protected short signed sizeof template this typedef typename union unsigned using virtual volatile " +
            "fn impl match mod move mut pub ref trait use val when fun").split(separator: " ").map(String.init))
        let characters = Array(source)
        var output: [MarkdownCodeToken] = []
        var index = 0
        var plainStart: Int?
        func append(_ start: Int, _ end: Int, _ style: MarkdownCodeToken.Style) {
            if style == .plain {
                if plainStart == nil { plainStart = start }
                return
            }
            if let pending = plainStart {
                output.append(.init(text: String(characters[pending..<start]), style: .plain))
                plainStart = nil
            }
            output.append(.init(text: String(characters[start..<end]), style: style))
        }
        while index < characters.count {
            // A styled token may flush one pending plain run before appending itself.
            // Stop before allocating past the run budget; retain the entire source.
            if output.count >= maximumTokens - 1 { return [.init(text: source, style: .plain)] }
            let start = index
            let ch = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : "\0"
            if ((python || shell) && ch == "#") || ((cFamily || language == "jsonc") && ch == "/" && next == "/") {
                while index < characters.count, characters[index] != "\n" { index += 1 }
                append(start, index, .comment); continue
            }
            if (cFamily || language == "jsonc"), ch == "/", next == "*" {
                index += 2
                var nesting = 1
                while index < characters.count, nesting > 0 {
                    if index + 1 < characters.count, characters[index] == "*", characters[index + 1] == "/" { nesting -= 1; index += 2 }
                    else if ["swift", "rust"].contains(language), index + 1 < characters.count, characters[index] == "/", characters[index + 1] == "*" { nesting += 1; index += 2 }
                    else { index += 1 }
                }
                append(start, index, .comment); continue
            }
            if ch == "\"" || (!json && (ch == "'" || ch == "`")) {
                let triple = (python || language == "swift") && index + 2 < characters.count && characters[index + 1] == ch && characters[index + 2] == ch
                let width = triple ? 3 : 1
                index += width
                while index < characters.count {
                    if characters[index] == "\\" { index = min(characters.count, index + 2); continue }
                    if triple {
                        if index + 2 < characters.count, characters[index] == ch, characters[index + 1] == ch, characters[index + 2] == ch { index += 3; break }
                    } else if characters[index] == ch { index += 1; break }
                    index += 1
                }
                append(start, index, .string); continue
            }
            if ch.isASCII && ch.isNumber {
                index += 1
                while index < characters.count, characters[index].isASCII && (characters[index].isNumber || characters[index].isLetter || characters[index] == "." || characters[index] == "_") { index += 1 }
                append(start, index, .number); continue
            }
            if ch.isLetter || ch == "_" || ch == "$" {
                index += 1
                while index < characters.count, characters[index].isLetter || characters[index].isNumber || characters[index] == "_" || characters[index] == "$" { index += 1 }
                let word = String(characters[start..<index])
                append(start, index, keywords.contains(word) ? .keyword : .plain); continue
            }
            index += 1
            append(start, index, .plain)
        }
        if let pending = plainStart {
            output.append(.init(text: String(characters[pending..<characters.count]), style: .plain))
        }
        return output
    }
}
