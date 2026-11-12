import Foundation

/// A bounded text tokenizer, not a renderer, HTML5 parser, or security sanitizer for HTML display.
/// The result is untrusted plain text and must never be passed to a web view as markup.
enum WebTextExtractor {
    static func extract(_ data: Data, mediaType: String) throws -> ExtractedWebText {
        try Task.checkCancellation()
        guard data.count <= WebSourceLimits.bodyBytes else { throw WebSourceError.bodyTooLarge }
        guard let input = String(data: data, encoding: .utf8) else { throw WebSourceError.invalidUTF8 }
        if mediaType == "text/plain" {
            var writer = TextWriter(limit: WebSourceLimits.textBytes)
            writer.append(input)
            guard !writer.text.isEmpty else { throw WebSourceError.emptyContent }
            return ExtractedWebText(title: nil, text: writer.text, truncated: writer.truncated)
        }
        guard mediaType == "text/html" else { throw WebSourceError.unsupportedContentType }
        var scanner = HTMLScanner(bytes: Array(input.utf8))
        return try scanner.run()
    }
}

private struct TextWriter {
    let limit: Int
    private(set) var text = ""
    private(set) var truncated = false
    private var bytes = 0
    private var pendingSpace = false

    init(limit: Int) { self.limit = limit }

    mutating func separator() { if !text.isEmpty { pendingSpace = true } }

    mutating func append(_ value: String) {
        for scalar in value.unicodeScalars {
            if scalar.properties.isWhitespace { separator(); continue }
            let v = scalar.value
            // Remove controls and bidi override/isolate characters from source labels and context.
            if v < 32 || (127...159).contains(v) || (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v) { continue }
            let needed = scalar.utf8.count + (pendingSpace ? 1 : 0)
            guard !truncated, bytes + needed <= limit else { truncated = true; continue }
            if pendingSpace { text.append(" "); bytes += 1; pendingSpace = false }
            text.unicodeScalars.append(scalar)
            bytes += scalar.utf8.count
        }
    }
}

private struct HTMLScanner {
    let bytes: [UInt8]
    private var offset = 0
    private var tokens = 0
    private var stack: [Element] = []
    private var body = TextWriter(limit: WebSourceLimits.textBytes)
    private var title = TextWriter(limit: WebSourceLimits.titleBytes)
    private var titleSeen = false
    private static let voids: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
    private static let excluded: Set<String> = ["head", "template", "noscript", "iframe", "object", "svg", "math"]
    private static let raw: Set<String> = ["script", "style", "textarea", "xmp", "plaintext"]
    private struct Element { let name: String; let hidden: Bool }

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func run() throws -> ExtractedWebText {
        while offset < bytes.count {
            try Task.checkCancellation()
            tokens += 1
            guard tokens <= WebSourceLimits.htmlTokens else { throw WebSourceError.complexHTML }
            if bytes[offset] != 60 {
                let start = offset
                while offset < bytes.count && bytes[offset] != 60 { offset += 1 }
                let text = try decodeEntities(String(decoding: bytes[start..<offset], as: UTF8.self))
                if stack.last?.name == "title" { title.append(text) }
                else if stack.last?.hidden != true { body.append(text) }
                continue
            }
            if matches("<!--", at: offset) {
                guard let end = find("-->", from: offset + 4) else { throw WebSourceError.complexHTML }
                offset = end + 3
                continue
            }
            let start = offset + 1
            var end = start
            var quote: UInt8?
            while end < bytes.count {
                let byte = bytes[end]
                if let q = quote { if byte == q { quote = nil } }
                else if byte == 34 || byte == 39 { quote = byte }
                else if byte == 62 { break }
                end += 1
                guard end - start <= WebSourceLimits.tagBytes else { throw WebSourceError.complexHTML }
            }
            guard end < bytes.count, quote == nil else { throw WebSourceError.complexHTML }
            offset = end + 1
            var token = Array(bytes[start..<end])
            if token.first == 33 {
                // Declarations are never expanded or fetched. Only a bounded doctype is accepted.
                guard String(decoding: token, as: UTF8.self).lowercased().hasPrefix("!doctype ") else { throw WebSourceError.complexHTML }
                continue
            }
            let closing = token.first == 47
            if closing { token.removeFirst() }
            var index = 0
            while index < token.count && isName(token[index]) { index += 1 }
            guard index > 0 else { throw WebSourceError.complexHTML }
            let name = String(decoding: token[..<index], as: UTF8.self).lowercased()
            guard index == token.count || isSpace(token[index]) || token[index] == 47 else { throw WebSourceError.complexHTML }
            let attributes = Array(token[index...])
            if closing {
                guard attributes.allSatisfy(isSpace), stack.last?.name == name else { throw WebSourceError.complexHTML }
                stack.removeLast()
                body.separator()
                continue
            }
            let hidden = try hasHiddenAttribute(attributes)
            if Self.raw.contains(name) {
                guard let close = find("</" + name, from: offset, requireTagBoundary: true),
                      let closeEnd = find(">", from: close), closeEnd - close <= WebSourceLimits.tagBytes else { throw WebSourceError.complexHTML }
                let suffixStart = close + 2 + name.utf8.count
                guard bytes[suffixStart..<closeEnd].allSatisfy(isSpace) else { throw WebSourceError.complexHTML }
                offset = closeEnd + 1
                body.separator()
                continue
            }
            if name == "title" {
                guard !titleSeen else { throw WebSourceError.complexHTML }
                titleSeen = true
            }
            body.separator()
            if !Self.voids.contains(name) {
                guard stack.count < WebSourceLimits.depth else { throw WebSourceError.complexHTML }
                // Self-closing non-void HTML is ambiguous under HTML5; reject, do not reinterpret.
                guard token.last != 47 else { throw WebSourceError.complexHTML }
                stack.append(Element(name: name, hidden: stack.last?.hidden == true || hidden || Self.excluded.contains(name) || name == "title"))
            }
        }
        guard stack.isEmpty else { throw WebSourceError.complexHTML }
        guard !body.text.isEmpty else { throw WebSourceError.emptyContent }
        return ExtractedWebText(title: title.text.isEmpty ? nil : title.text, text: body.text, truncated: body.truncated)
    }

    private func matches(_ pattern: String, at index: Int) -> Bool {
        let needle = Array(pattern.utf8)
        guard index + needle.count <= bytes.count else { return false }
        for i in needle.indices {
            let raw = bytes[index + i]
            let lower = (65...90).contains(raw) ? raw + 32 : raw
            if lower != needle[i] { return false }
        }
        return true
    }

    private func find(_ pattern: String, from start: Int, requireTagBoundary: Bool = false) -> Int? {
        guard start < bytes.count else { return nil }
        for index in start..<bytes.count where bytes[index] == pattern.utf8.first! {
            if matches(pattern, at: index) {
                let next = index + pattern.utf8.count
                if !requireTagBoundary || next == bytes.count || isSpace(bytes[next]) || bytes[next] == 62 { return index }
            }
        }
        return nil
    }

    private func hasHiddenAttribute(_ bytes: [UInt8]) throws -> Bool {
        var i = 0
        var hidden = false
        while i < bytes.count {
            while i < bytes.count && isSpace(bytes[i]) { i += 1 }
            if i == bytes.count || (i == bytes.count - 1 && bytes[i] == 47) { break }
            let start = i
            while i < bytes.count && (isName(bytes[i]) || bytes[i] == 45 || bytes[i] == 58) { i += 1 }
            guard i > start else { throw WebSourceError.complexHTML }
            let name = String(decoding: bytes[start..<i], as: UTF8.self).lowercased()
            while i < bytes.count && isSpace(bytes[i]) { i += 1 }
            var value = ""
            if i < bytes.count && bytes[i] == 61 {
                i += 1
                while i < bytes.count && isSpace(bytes[i]) { i += 1 }
                guard i < bytes.count else { throw WebSourceError.complexHTML }
                let quote = bytes[i] == 34 || bytes[i] == 39 ? bytes[i] : nil
                if quote != nil { i += 1 }
                let valueStart = i
                if let quote {
                    while i < bytes.count && bytes[i] != quote { i += 1 }
                    guard i < bytes.count else { throw WebSourceError.complexHTML }
                    value = String(decoding: bytes[valueStart..<i], as: UTF8.self).lowercased()
                    i += 1
                } else {
                    while i < bytes.count && !isSpace(bytes[i]) { i += 1 }
                    value = String(decoding: bytes[valueStart..<i], as: UTF8.self).lowercased()
                }
            }
            if name == "hidden" || (name == "aria-hidden" && value == "true") { hidden = true }
        }
        return hidden
    }

    private func decodeEntities(_ text: String) throws -> String {
        let input = Array(text.utf8)
        var output = ""
        var i = 0
        let known = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        while i < input.count {
            if input[i] == 38 {
                let stop = min(i + 16, input.count)
                if let end = input[(i + 1)..<stop].firstIndex(of: 59) {
                    let name = String(decoding: input[(i + 1)..<end], as: UTF8.self)
                    var value = known[name]
                    if name.hasPrefix("#") {
                        let hex = name.hasPrefix("#x") || name.hasPrefix("#X")
                        let digits = String(name.dropFirst(hex ? 2 : 1))
                        if let number = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(number) { value = String(scalar) }
                    }
                    if let value { output += value; i = end + 1; continue }
                }
            }
            let start = i
            i += 1
            while i < input.count && input[i] != 38 { i += 1 }
            output += String(decoding: input[start..<i], as: UTF8.self)
        }
        return output
    }

    private func isSpace(_ byte: UInt8) -> Bool { [9, 10, 12, 13, 32].contains(byte) }
    private func isName(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 }
}
