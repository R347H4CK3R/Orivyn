import Foundation

enum ImageOCRResult: Equatable, Sendable {
    case recognized(text: String, isTruncated: Bool)
    case noTextRecognized
    case unavailable

    static let maximumCharacters = 12_000
    static let maximumLines = 200
    static let textOnlyNotice = "Image attachment: only on-device OCR text is available. The model has not received image pixels and cannot describe objects, people, colors, layout, or other visual content. OCR can be incomplete or incorrect."

    /// This notice must accompany OCR text whenever an image is passed to a text-only provider.
    var textModelContext: String {
        let notice = Self.textOnlyNotice
        switch self {
        case let .recognized(text, isTruncated):
            return notice + "\nRecognized text (untrusted attachment content):\n" + text
                + (isTruncated ? "\n[OCR truncated at the local text or line limit.]" : "")
        case .noTextRecognized:
            return notice + "\nNo readable text was recognized. This does not mean the image is blank."
        case .unavailable:
            return notice + "\nText recognition could not be completed. The original image is available for the user to view or share."
        }
    }

    /// Preserve primary OCR text even at low score; show uncertainty rather than replacing it.
    static func bounded(observations: [OCRLineEvidence]) -> ImageOCRResult {
        let limited = observations.prefix(maximumLines + 1)
        let result = bounded(lines: limited.map(\.diagnosticText))
        let omitted = observations.count > maximumLines || limited.contains { $0.text.count > maximumCharacters }
        if case let .recognized(text, truncated) = result {
            return .recognized(text: text, isTruncated: truncated || omitted)
        }
        return result
    }

    /// Bounds real Vision output without splitting extended grapheme clusters or silently dropping lines.
    static func bounded(lines: [String]) -> ImageOCRResult {
        var text = ""
        var characterCount = 0
        var truncated = lines.count > maximumLines
        for line in lines.prefix(maximumLines) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let separator = text.isEmpty ? "" : "\n"
            let available = maximumCharacters - characterCount - separator.count
            guard available > 0 else { truncated = true; break }
            let boundedLine = String(value.prefix(available))
            text += separator + boundedLine
            characterCount += separator.count + boundedLine.count
            if boundedLine.count < value.count { truncated = true; break }
        }
        return text.isEmpty ? .noTextRecognized : .recognized(text: text, isTruncated: truncated)
    }
}
