import Foundation

/// A reviewed patch is exportable only while its exact input bytes are unchanged.
/// Swift String equality treats canonically equivalent Unicode as equal; source
/// exports need byte identity, including normalization and line endings.
struct SourceRepairReviewBinding: Sendable {
    private let replacementBytes: Data
    private let summaryBytes: Data

    init(replacement: String, summary: String) {
        replacementBytes = Data(replacement.utf8)
        summaryBytes = Data(summary.utf8)
    }

    func matches(replacement: String, summary: String) -> Bool {
        replacementBytes.elementsEqual(replacement.utf8) && summaryBytes.elementsEqual(summary.utf8)
    }
}
