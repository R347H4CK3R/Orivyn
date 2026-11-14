import XCTest
@testable import JarvisEVO

final class OCRLineEvidenceTests: XCTestCase {
    func testLowConfidenceTextIsPreservedRatherThanInventedOrDropped() {
        let item = OCRLineEvidence(text: "ALTO 73", confidence: 0.2, alternate: "ALTO 78")
        let result = ImageOCRResult.bounded(observations: [item])
        guard case let .recognized(text, truncated) = result else { return XCTFail("Lost actual OCR") }
        XCTAssertTrue(text.contains("ALTO 73"))
        XCTAssertTrue(text.contains("0.200"))
        XCTAssertTrue(text.contains("not a correctness probability"))
        XCTAssertTrue(text.contains("not a correction"))
        XCTAssertTrue(text.contains("ALTO 78"))
        XCTAssertFalse(truncated)
    }
    func testInvalidScoresAndTruncatedLinesAreExplicit() {
        let item = OCRLineEvidence(text: "actual", confidence: .nan, alternate: nil)
        XCTAssertTrue(item.diagnosticText.contains("score unavailable"))
        let huge = OCRLineEvidence(text: String(repeating: "x", count: 20_000), confidence: 0.99, alternate: nil)
        guard case let .recognized(text, truncated) = ImageOCRResult.bounded(observations: [huge]) else { return XCTFail("Missing bounded OCR") }
        XCTAssertTrue(truncated)
        XCTAssertLessThanOrEqual(text.count, ImageOCRResult.maximumCharacters)
        XCTAssertEqual(ImageOCRResult.bounded(observations: []), .noTextRecognized)
    }
}
