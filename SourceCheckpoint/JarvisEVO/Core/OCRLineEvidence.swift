import Foundation

/// Recognizer scores are diagnostic values, not calibrated probabilities of correctness.
struct OCRLineEvidence: Equatable, Sendable {
    let text: String
    let confidence: Float
    let alternate: String?

    var diagnosticText: String {
        let score: String
        if confidence.isFinite && (0...1).contains(confidence) {
            score = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(confidence))
        } else { score = "unavailable" }
        let low = confidence.isFinite && confidence < 0.5 ? "; low recognizer score" : ""
        var value = "[OCR score \(score)\(low); not a correctness probability] " + String(text.prefix(ImageOCRResult.maximumCharacters))
        if let alternate, !alternate.isEmpty, alternate != text {
            value += "\n[Alternative OCR candidate, not a correction] " + String(alternate.prefix(200))
            if alternate.count > 200 { value += " [alternative shortened]" }
        }
        return value
    }
}
