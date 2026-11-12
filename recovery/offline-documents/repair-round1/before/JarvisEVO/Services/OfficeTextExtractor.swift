import Foundation

private enum OfficeNS {
    static let word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    static let sheet = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    static let relationship = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let officeRelationship = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let contentType = "http://schemas.openxmlformats.org/package/2006/content-types"
}
private struct OfficeRelationship {
    let type: String
    let target: String
    let external: Bool
}

struct OfficeTextExtractor {
    let package: OfficeZIPContainer
    let limits: OfflineDocumentLimits

    func read(format: OfflineDocumentFormat) throws -> OfflineDocumentResult {
        let graph = try relationships()
        guard let roots = graph[""], roots.values.filter({ $0.type == OfficeNS.officeRelationship + "/officeDocument" }).count == 1,
              let main = roots.values.first(where: { $0.type == OfficeNS.officeRelationship + "/officeDocument" }),
              !main.external else { throw OfflineDocumentError.invalidPackage }
        let types = try xml("[Content_Types].xml")
        guard types.name == "Types", types.namespace == OfficeNS.contentType else { throw OfflineDocumentError.invalidPackage }
        let expected = format == .docx
            ? "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"
            : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"
        let overrides = types.children("Override",in: OfficeNS.contentType)
        guard overrides.filter({ $0.attribute("PartName") == "/" + main.target && $0.attribute("ContentType") == expected }).count == 1 else {
            throw OfflineDocumentError.invalidPackage
        }
        for child in types.children {
            let type = (child.attribute("ContentType") ?? "").lowercased()
            guard !type.contains("macro"), !type.contains("vba"), !type.contains("activex"), !type.contains("oleobject") else {
                throw OfflineDocumentError.unsafeArchive
            }
        }
        var notes = ["Text only. Original layout, charts, images, scanned pages and embedded objects are not interpreted. Office code and formulas are not executed."]
        if graph.values.contains(where: { $0.values.contains(where: \.external) }) {
            notes.append("External hyperlinks are omitted and never opened.")
        }
        switch format {
        case .docx:
            notes.append("DOCX body paragraphs and table cells only. Headers, footers, comments, footnotes, text boxes, drawings, deleted text and field instructions are omitted. Lists and formatting are approximate.")
            return try word(main.target,notes: notes)
        case .xlsx:
            notes.append("XLSX stored cell values only. Formula values are cached and may be stale; missing caches are labeled. Numeric spelling is preserved. Dates stay as raw serials with epoch/format, not guessed conversions. Hidden sheets/rows are labeled. Merges, filters, number formatting and charts are not reproduced.")
            return try workbook(main.target,graph: graph,notes: notes)
        default: throw OfflineDocumentError.unsupportedFormat
        }
    }
    private func xml(_ name: String) throws -> OfficeXMLNode {
        guard let data = package.parts[name] else { throw OfflineDocumentError.invalidPackage }
        return try BoundedOfficeXML.parse(data,limits: limits)
    }

    /// OPC relationships resolve only to package keys, never file URLs. Relative parent segments
    /// are permitted only while the canonical result remains inside the package (e.g. ../styles.xml).
    private func resolve(_ target: String, source: String) throws -> String {
        guard !target.isEmpty, target.utf8.count <= 255, !target.contains("\\"), !target.contains(":"),
              !target.contains("%"), !target.contains("?"), !target.contains("#"),
              target.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { throw OfflineDocumentError.invalidPackage }
        var parts = target.hasPrefix("/") || source.isEmpty ? [] : source.split(separator: "/").dropLast().map(String.init)
        let raw = target.hasPrefix("/") ? String(target.dropFirst()) : target
        for segment in raw.split(separator: "/",omittingEmptySubsequences: false) {
            guard !segment.isEmpty, segment != "." else { throw OfflineDocumentError.invalidPackage }
            if segment == ".." {
                guard !parts.isEmpty else { throw OfflineDocumentError.invalidPackage }
                parts.removeLast()
            } else { parts.append(String(segment)) }
        }
        let path = parts.joined(separator: "/")
        guard package.names.contains(path) else { throw OfflineDocumentError.invalidPackage }
        return path
    }
    private func relationships() throws -> [String:[String:OfficeRelationship]] {
        var result = [String:[String:OfficeRelationship]]()
        for name in package.parts.keys.sorted() where name.hasSuffix(".rels") {
            try Task.checkCancellation()
            let source: String
            if name == "_rels/.rels" { source = "" }
            else {
                let pieces = name.split(separator: "/").map(String.init)
                guard pieces.count >= 2, pieces[pieces.count-2] == "_rels", let filename = pieces.last else { throw OfflineDocumentError.invalidPackage }
                source = (Array(pieces.dropLast(2)) + [String(filename.dropLast(5))]).joined(separator: "/")
                guard package.names.contains(source) else { throw OfflineDocumentError.invalidPackage }
            }
            let root = try xml(name)
            guard root.name == "Relationships", root.namespace == OfficeNS.relationship else { throw OfflineDocumentError.invalidPackage }
            var map = [String:OfficeRelationship]()
            for child in root.children {
                guard child.name == "Relationship", child.namespace == OfficeNS.relationship,
                      let id = child.attribute("Id"), !id.isEmpty, map[id] == nil,
                      let type = child.attribute("Type"), let target = child.attribute("Target"),
                      child.attribute("TargetMode") == nil || ["Internal","External"].contains(child.attribute("TargetMode") ?? "") else { throw OfflineDocumentError.invalidPackage }
                let external = child.attribute("TargetMode") == "External"
                if external {
                    guard type == OfficeNS.officeRelationship + "/hyperlink" else { throw OfflineDocumentError.invalidPackage }
                    map[id] = OfficeRelationship(type: type,target: "",external: true)
                } else {
                    map[id] = OfficeRelationship(type: type,target: try resolve(target,source: source),external: false)
                }
            }
            guard result[source] == nil else { throw OfflineDocumentError.invalidPackage }
            result[source] = map
        }
        return result
    }

    private func word(_ path: String, notes: [String]) throws -> OfflineDocumentResult {
        let root = try xml(path), ns = OfficeNS.word
        guard root.name == "document", root.namespace == ns, root.children("body",in: ns).count == 1, let body = root.first("body",in: ns) else { throw OfflineDocumentError.invalidPackage }
        var output = OfficeTextOutput(maximum: limits.maximumOutputCharacters)
        func paragraph(_ node: OfficeXMLNode) -> String {
            guard node.namespace == ns else { return "" }
            if ["del","moveFrom","drawing","pict","object","txbxContent","instrText","delText"].contains(node.name) { return "" }
            switch node.name {
            case "t": return node.text
            case "tab": return "\t"
            case "br","cr": return "\n"
            default: return node.children.map(paragraph).joined()
            }
        }
        func blocks(_ node: OfficeXMLNode) throws {
            try Task.checkCancellation()
            guard node.namespace == ns else { return }
            if ["del","moveFrom","drawing","pict","object","txbxContent"].contains(node.name) { return }
            if node.name == "p" { output.append(paragraph(node) + "\n"); return }
            if node.name == "tbl" {
                for row in node.children("tr",in: ns) {
                    let cells = row.children("tc",in: ns).map { cell in
                        cell.children.map(paragraph).filter { !$0.isEmpty }.joined(separator: " / ")
                    }
                    output.append(cells.joined(separator: " | ") + "\n")
                }
                return
            }
            for child in node.children { try blocks(child) }
        }
        try blocks(body)
        guard !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OfflineDocumentError.noText }
        return OfflineDocumentResult(format: .docx,text: output.text,notes: notes,wasTruncated: output.truncated)
    }

    private func workbook(_ path: String, graph: [String:[String:OfficeRelationship]], notes: [String]) throws -> OfflineDocumentResult {
        let root = try xml(path), ns = OfficeNS.sheet
        guard root.name == "workbook", root.namespace == ns, root.children("sheets",in: ns).count == 1,
              root.children("workbookPr",in: ns).count <= 1,
              let sheets = root.first("sheets",in: ns), let rels = graph[path] else { throw OfflineDocumentError.invalidPackage }
        let epochValue = root.first("workbookPr",in: ns)?.attribute("date1904") ?? "0"
        guard ["0","1","true","false"].contains(epochValue) else { throw OfflineDocumentError.invalidPackage }
        let epoch = ["1","true"].contains(epochValue) ? "1904" : "1900"
        var strings = [String](), styles = [""], formatCodes = [Int:String]()
        func typedPart(_ type: String) throws -> String? {
            let matches = rels.values.filter { $0.type == OfficeNS.officeRelationship + "/" + type }
            guard matches.count <= 1, !matches.contains(where: \.external) else { throw OfflineDocumentError.invalidPackage }
            return matches.first?.target
        }
        func richText(_ node: OfficeXMLNode) throws -> String {
            var result = ""
            func gather(_ n: OfficeXMLNode) throws {
                guard n.namespace == ns, !["rPh","phoneticPr"].contains(n.name) else { return }
                if n.name == "t" {
                    guard n.text.utf8.count <= limits.maximumStringBytes - result.utf8.count else { throw OfflineDocumentError.limit("A spreadsheet string is too long.") }
                    result += n.text
                } else { for child in n.children { try gather(child) } }
            }
            try gather(node); return try Self.decodeSpreadsheetString(result)
        }
        if let sharedPath = try typedPart("sharedStrings") {
            let shared = try xml(sharedPath)
            guard shared.name == "sst", shared.namespace == ns else { throw OfflineDocumentError.invalidPackage }
            for si in shared.children("si",in: ns) {
                guard strings.count < limits.maximumSharedStrings else { throw OfflineDocumentError.limit("The workbook has too many shared strings.") }
                strings.append(try richText(si))
            }
        }
        if let stylePath = try typedPart("styles") {
            let style = try xml(stylePath)
            guard style.name == "styleSheet", style.namespace == ns else { throw OfflineDocumentError.invalidPackage }
            for fmt in style.first("numFmts",in: ns)?.children("numFmt",in: ns) ?? [] {
                guard let id = fmt.attribute("numFmtId").flatMap(Int.init), id >= 164, formatCodes[id] == nil, let code = fmt.attribute("formatCode") else { throw OfflineDocumentError.invalidPackage }
                formatCodes[id] = code
            }
            let xfs = style.first("cellXfs",in: ns)?.children("xf",in: ns) ?? []
            if !xfs.isEmpty { styles.removeAll(keepingCapacity: true) }
            for xf in xfs {
                guard let id = Int(xf.attribute("numFmtId") ?? "0"), id >= 0 else { throw OfflineDocumentError.invalidPackage }
                if (14...22).contains(id) || (27...36).contains(id) || (45...47).contains(id) || (50...58).contains(id) {
                    styles.append("date/time format #\(id)")
                } else if let code = formatCodes[id] { styles.append("format \(code)") }
                else { styles.append("") }
            }
        }
        var output = OfficeTextOutput(maximum: limits.maximumOutputCharacters), rowsSeen = 0, cellsSeen = 0
        var sheetIDs = Set<String>(), sheetNames = Set<String>(), sheetTargets = Set<String>(), numericSheetIDs = Set<Int>(), hasValue = false
        let sheetNodes = sheets.children("sheet",in: ns)
        guard !sheetNodes.isEmpty, sheetNodes.count <= limits.maximumWorksheets else { throw OfflineDocumentError.limit("The workbook has no sheets or too many worksheets.") }
        for sheet in sheetNodes {
            try Task.checkCancellation()
            guard let name = sheet.attribute("name"), !name.isEmpty, sheetNames.insert(name.lowercased()).inserted,
                  let numericID = sheet.attribute("sheetId").flatMap(Int.init), numericID > 0, numericID <= Int(UInt32.max), numericSheetIDs.insert(numericID).inserted,
                  let id = sheet.attribute("id",namespace: OfficeNS.officeRelationship), sheetIDs.insert(id).inserted,
                  let relation = rels[id], relation.type == OfficeNS.officeRelationship + "/worksheet", !relation.external,
                  sheetTargets.insert(relation.target).inserted else { throw OfflineDocumentError.invalidPackage }
            let state = sheet.attribute("state") ?? "visible"
            guard ["visible","hidden","veryHidden"].contains(state) else { throw OfflineDocumentError.invalidPackage }
            output.append("Worksheet: \(escaped(try Self.decodeSpreadsheetString(name)))\(state == "visible" ? "" : " (\(state))")\n")
            let worksheet = try xml(relation.target)
            guard worksheet.name == "worksheet", worksheet.namespace == ns,
                  worksheet.children("sheetData",in: ns).count <= 1 else { throw OfflineDocumentError.invalidPackage }
            guard let data = worksheet.first("sheetData",in: ns) else { continue }
            var previousRow = 0
            for row in data.children("row",in: ns) {
                try Task.checkCancellation()
                let rowNumber: Int
                if let rawRow = row.attribute("r") {
                    guard let parsed = Int(rawRow), String(parsed) == rawRow else { throw OfflineDocumentError.invalidPackage }
                    rowNumber = parsed
                } else { rowNumber = previousRow + 1 }
                guard rowNumber > previousRow, rowNumber <= 1_048_576 else { throw OfflineDocumentError.invalidPackage }
                previousRow = rowNumber; rowsSeen += 1
                let hidden = row.attribute("hidden") ?? "0"
                guard ["0","1","true","false"].contains(hidden) else { throw OfflineDocumentError.invalidPackage }
                var parts = [String](), previousColumn = 0
                for cell in row.children("c",in: ns) {
                    try Task.checkCancellation()
                    let coordinate: (column: Int,row: Int,label: String)
                    if let ref = cell.attribute("r") { coordinate = try Self.coordinate(ref) }
                    else { coordinate = (previousColumn+1,rowNumber,Self.columnName(previousColumn+1)+String(rowNumber)) }
                    guard coordinate.row == rowNumber, coordinate.column > previousColumn, coordinate.column <= 16_384 else { throw OfflineDocumentError.invalidPackage }
                    previousColumn = coordinate.column; cellsSeen += 1
                    let type = cell.attribute("t") ?? "n"
                    let values = cell.children("v",in: ns), formulas = cell.children("f",in: ns), inline = cell.children("is",in: ns)
                    guard values.count <= 1, formulas.count <= 1, inline.count <= 1 else { throw OfflineDocumentError.invalidPackage }
                    let raw = values.first?.text, formula = !formulas.isEmpty
                    let hasCache = raw != nil && (raw?.isEmpty == false || type == "str")
                    let value: String
                    if formula && !hasCache {
                        guard ["s","n","b","e","d","str"].contains(type), inline.isEmpty else { throw OfflineDocumentError.invalidPackage }
                        value = ""
                    } else {
                    switch type {
                    case "s":
                        guard inline.isEmpty else { throw OfflineDocumentError.invalidPackage }
                        if formula && (raw == nil || raw == "") { value = "" }
                        else {
                            guard let index = raw.flatMap(Int.init), index >= 0, index < strings.count else { throw OfflineDocumentError.invalidPackage }
                            value = strings[index]
                        }
                    case "inlineStr":
                        guard !formula, values.isEmpty, let isNode = inline.first else { throw OfflineDocumentError.invalidPackage }
                        value = try richText(isNode)
                    case "b":
                        guard inline.isEmpty, raw == nil || ["0","1"].contains(raw!) else { throw OfflineDocumentError.invalidPackage }
                        value = raw.map { $0 == "1" ? "TRUE" : "FALSE" } ?? ""
                    case "e":
                        guard inline.isEmpty else { throw OfflineDocumentError.invalidPackage }
                        value = raw.map { "[error: \($0)]" } ?? ""
                    case "d":
                        guard inline.isEmpty, raw == nil || Self.isISODate(raw!) else { throw OfflineDocumentError.invalidPackage }
                        // ISO dates are kept verbatim; the model is not given an invented conversion.
                        value = raw.map { "\($0) [ISO date stored by workbook]" } ?? ""
                    case "str":
                        guard inline.isEmpty else { throw OfflineDocumentError.invalidPackage }
                        value = try Self.decodeSpreadsheetString(raw ?? "")
                    case "n":
                        guard inline.isEmpty else { throw OfflineDocumentError.invalidPackage }
                        if let raw, !raw.isEmpty {
                            guard let number = Double(raw), number.isFinite, raw.utf8.count <= 128,
                                  raw.utf8.allSatisfy({ (48...57).contains($0) || [43,45,46,69,101].contains($0) }) else { throw OfflineDocumentError.invalidPackage }
                            if let styleText = cell.attribute("s") {
                                guard let index = Int(styleText), index >= 0, index < styles.count else { throw OfflineDocumentError.invalidPackage }
                                let style = styles[index]
                                if style.hasPrefix("date/time") {
                                    value = "\(raw) [serial \(raw); \(epoch) epoch; \(style)]"
                                } else {
                                    value = style.isEmpty ? raw : "\(raw) [\(style); \(epoch) date epoch if interpreted as a date]"
                                }
                            } else { value = raw }
                        } else { value = "" }
                    default: throw OfflineDocumentError.invalidPackage
                    }
                    }
                    if let styleText = cell.attribute("s") {
                        guard let index = Int(styleText), index >= 0, index < styles.count else { throw OfflineDocumentError.invalidPackage }
                    }
                    let rendered = formula ? (hasCache ? "[cached formula value: \(escaped(value))]" : "[formula cache unavailable]") : escaped(value)
                    if !rendered.isEmpty { hasValue = true }
                    if rowsSeen <= limits.maximumRows, cellsSeen <= limits.maximumCells {
                        parts.append("\(coordinate.label)=\(rendered)")
                    } else { output.truncated = true }
                }
                if rowsSeen <= limits.maximumRows, !parts.isEmpty {
                    output.append("Row \(rowNumber)\(["1","true"].contains(hidden) ? " (hidden)" : ""): " + parts.joined(separator: " | ") + "\n")
                } else if rowsSeen > limits.maximumRows { output.truncated = true }
            }
        }
        guard hasValue else { throw OfflineDocumentError.noText }
        return OfflineDocumentResult(format: .xlsx,text: output.text,notes: notes,wasTruncated: output.truncated)
    }

    private func escaped(_ value: String) -> String {
        OfficeTextEscaping.render(value)
    }
    private static func decodeSpreadsheetString(_ raw: String) throws -> String {
        // SpreadsheetML ST_Xstring escapes UTF-16 units as _xHHHH_. Decode from the
        // ORIGINAL sequence once, so _x005F_x0041_ correctly stays the literal _x0041_.
        let units = Array(raw.utf16)
        var result = [UInt16](), index = 0
        while index < units.count {
            if index + 6 < units.count, units[index] == 95, units[index+1] == 120, units[index+6] == 95 {
                let digits = String(decoding: units[(index+2)..<(index+6)],as: UTF16.self)
                if digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                   let unit = UInt16(digits,radix: 16) {
                    result.append(unit); index += 7; continue
                }
            }
            result.append(units[index]); index += 1
        }
        var check = 0
        while check < result.count {
            let unit = result[check]
            if (0xd800...0xdbff).contains(unit) {
                guard check+1 < result.count, (0xdc00...0xdfff).contains(result[check+1]) else { throw OfflineDocumentError.invalidPackage }
                check += 2
            } else {
                guard !(0xdc00...0xdfff).contains(unit) else { throw OfflineDocumentError.invalidPackage }
                check += 1
            }
        }
        return String(decoding: result,as: UTF16.self)
    }
    private static func isISODate(_ value: String) -> Bool {
        // Validate the calendar date and conventional ISO time syntax without changing its spelling.
        let pattern = #"^[0-9]{4}-[0-9]{2}-[0-9]{2}(T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]{1,9})?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])?)?$"#
        guard value.range(of: pattern,options: .regularExpression) != nil else { return false }
        let datePart = String(value.prefix(10)).split(separator: "-").compactMap { Int($0) }
        guard datePart.count == 3, datePart[0] > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: datePart[0],month: datePart[1],day: datePart[2])
        guard let date = calendar.date(from: components) else { return false }
        let actual = calendar.dateComponents([.year,.month,.day],from: date)
        return actual.year == datePart[0] && actual.month == datePart[1] && actual.day == datePart[2]
    }
    private static func coordinate(_ ref: String) throws -> (column: Int,row: Int,label: String) {
        guard ref.utf8.count <= 10 else { throw OfflineDocumentError.invalidPackage }
        var column = 0, rowText = "", inRow = false
        for byte in ref.utf8 {
            if (65...90).contains(byte), !inRow { column = column*26+Int(byte-64) }
            else if (48...57).contains(byte) { inRow = true; rowText.unicodeScalars.append(UnicodeScalar(byte)) }
            else { throw OfflineDocumentError.invalidPackage }
        }
        guard column > 0, column <= 16_384, let row = Int(rowText), row > 0, row <= 1_048_576,
              String(row) == rowText else { throw OfflineDocumentError.invalidPackage }
        return (column,row,ref)
    }
    static func columnName(_ column: Int) -> String {
        var number = column, result = ""
        while number > 0 { number -= 1; result = String(UnicodeScalar(65 + number%26)!) + result; number /= 26 }
        return result
    }
}
