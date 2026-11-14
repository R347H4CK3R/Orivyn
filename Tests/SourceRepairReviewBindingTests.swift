import XCTest
@testable import JarvisEVO

final class SourceRepairReviewBindingTests: XCTestCase {
    func testExactReviewedBytesRemainEligible() {
        let binding = SourceRepairReviewBinding(replacement: "let x = 2\n", summary: "Update value")
        XCTAssertTrue(binding.matches(replacement: "let x = 2\n", summary: "Update value"))
    }

    func testEditingSourceOrSummaryInvalidatesReview() {
        let binding = SourceRepairReviewBinding(replacement: "let x = 2\n", summary: "Update value")
        XCTAssertFalse(binding.matches(replacement: "let x = 3\n", summary: "Update value"))
        XCTAssertFalse(binding.matches(replacement: "let x = 2\n", summary: "Different change"))
    }

    func testLineEndingAndFinalNewlineChangesRequireNewReview() {
        let binding = SourceRepairReviewBinding(replacement: "a\nb\n", summary: "Update")
        XCTAssertFalse(binding.matches(replacement: "a\r\nb\r\n", summary: "Update"))
        XCTAssertFalse(binding.matches(replacement: "a\nb", summary: "Update"))
    }

    func testEquivalentUnicodeIsNotEquivalentSourceBytes() {
        let composed = "caf\u{e9}", decomposed = "cafe\u{301}"
        XCTAssertEqual(composed, decomposed)
        let binding = SourceRepairReviewBinding(replacement: composed, summary: composed)
        XCTAssertFalse(binding.matches(replacement: decomposed, summary: composed))
        XCTAssertFalse(binding.matches(replacement: composed, summary: decomposed))
        XCTAssertTrue(binding.matches(replacement: composed, summary: composed))
    }
}
