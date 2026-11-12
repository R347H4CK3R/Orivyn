import Foundation

/// RFC-4180-style UTF-8 delimited records (CSV comma or TSV tab), never spreadsheet evaluation.
/// Fully validates the bounded input, while retaining only a bounded number of rows/cells.
enum DelimitedDocumentReader {
    static func read(_ data: Data, format: OfflineDocumentFormat, limits: OfflineDocumentLimits) throws -> OfflineDocumentResult {
        guard format == .csv || format == .tsv, var text = String(data: data,encoding: .utf8),
              !text.contains("\0") else { throw OfflineDocumentError.invalidDelimitedText }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let delimiter: UnicodeScalar = format == .csv ? "," : "\t"
        let scalars = text.unicodeScalars
        var index = scalars.startIndex, field = "", fieldBytes = 0, row = [String]()
        var quoted = false, afterQuote = false, fieldStarted = false, pendingRecord = false
        var rowNumber = 0, totalCells = 0, iterations = 0, hasValue = false
        var output = OfficeTextOutput(maximum: limits.maximumOutputCharacters)
        func escaped(_ value: String) -> String {
            OfficeTextEscaping.render(value)
        }
        func add(_ scalar: UnicodeScalar) throws {
            let bytes = scalar.utf8.count
            guard bytes <= limits.maximumStringBytes - fieldBytes else { throw OfflineDocumentError.limit("A delimited field exceeds the string limit.") }
            field.unicodeScalars.append(scalar); fieldBytes += bytes
        }
        func finishField() {
            totalCells += 1
            if !field.isEmpty { hasValue = true }
            if rowNumber < limits.maximumRows, totalCells <= limits.maximumCells { row.append(field) }
            else { output.truncated = true }
            field = ""; fieldBytes = 0; fieldStarted = false; afterQuote = false
        }
        func finishRecord() {
            finishField(); rowNumber += 1
            if rowNumber <= limits.maximumRows, !row.isEmpty {
                let parts = row.enumerated().map { "\(OfficeTextExtractor.columnName($0.offset+1))=\(escaped($0.element))" }
                output.append("Row \(rowNumber): " + parts.joined(separator: " | ") + "\n")
            } else { output.truncated = true }
            row.removeAll(keepingCapacity: true); pendingRecord = false
        }
        while index < scalars.endIndex {
            iterations += 1
            if iterations % 4_096 == 0 { try Task.checkCancellation() }
            let scalar = scalars[index]
            index = scalars.index(after: index)
            if quoted {
                if scalar == "\"" {
                    if index < scalars.endIndex, scalars[index] == "\"" { try add("\""); index = scalars.index(after: index) }
                    else { quoted = false; afterQuote = true }
                } else { try add(scalar) }
                pendingRecord = true; continue
            }
            if scalar == delimiter { finishField(); pendingRecord = true; continue }
            if scalar == "\r" || scalar == "\n" {
                if scalar == "\r", index < scalars.endIndex, scalars[index] == "\n" { index = scalars.index(after: index) }
                finishRecord(); continue
            }
            if afterQuote { throw OfflineDocumentError.invalidDelimitedText }
            if scalar == "\"" {
                guard !fieldStarted else { throw OfflineDocumentError.invalidDelimitedText }
                quoted = true; fieldStarted = true; pendingRecord = true
            } else {
                try add(scalar); fieldStarted = true; pendingRecord = true
            }
        }
        guard !quoted else { throw OfflineDocumentError.invalidDelimitedText }
        if pendingRecord || !field.isEmpty || !row.isEmpty { finishRecord() }
        guard hasValue else { throw OfflineDocumentError.noText }
        let notes = ["Text only. Delimited values are preserved as text; formulas and Office code are not executed. Quotes follow CSV rules; embedded line breaks, tabs, backslashes and column separators are escaped. The first row is not assumed to be a header. Delimiter: \(format == .csv ? "comma" : "tab")."]
        return OfflineDocumentResult(format: format,text: output.text,notes: notes,wasTruncated: output.truncated)
    }
}
