import XCTest
@testable import JarvisEVO

final class MemoryContextBuilderTests: XCTestCase {
    func testBudgetIncludesDisclaimerAndDelimiters() {
        let notes = (0..<12).map { MemoryNote(content: String(repeating: "Saved preference ", count: 100), createdAt: Date(timeIntervalSince1970: Double($0))) }
        for budget in [0, 1, 80, 200, 1024] {
            let result = MemoryContextBuilder.build(notes: notes, query: "preference", maximumBytes: budget)
            XCTAssertLessThanOrEqual(result.text.utf8.count, budget)
            XCTAssertLessThanOrEqual(result.includedCount, 8)
            XCTAssertTrue(result.truncated)
        }
    }
    func testASCIIExcerptFillsExactByteBudgetWithoutOverflow() {
        let result = MemoryContextBuilder.build(notes: [MemoryNote(content: String(repeating: "x", count: 5000))], query: "", maximumBytes: 1024)
        XCTAssertEqual(result.text.utf8.count, 1024)
        XCTAssertEqual(result.includedCount, 1)
        XCTAssertTrue(result.truncated)
    }
    func testMultibyteContentRemainsValidUTF8WithinBudget() {
        let note = MemoryNote(content: String(repeating: "日本語🦉e\u{301}", count: 1000))
        let result = MemoryContextBuilder.build(notes: [note], query: "日本語", maximumBytes: 251)
        XCTAssertLessThanOrEqual(result.text.utf8.count, 251)
        XCTAssertEqual(String(data: Data(result.text.utf8), encoding: .utf8), result.text)
        XCTAssertEqual(result.includedCount, 1)
        XCTAssertTrue(result.truncated)
    }
    func testOlderLexicalMatchWinsOverRecentUnrelatedNote() {
        let old = MemoryNote(content: "Café preference: oat milk", createdAt: Date(timeIntervalSince1970: 1))
        let recent = MemoryNote(content: "Gaming keyboard", createdAt: Date(timeIntervalSince1970: 100))
        let result = MemoryContextBuilder.build(notes: [recent, old], query: "CAFE milk", maximumNotes: 1)
        XCTAssertTrue(result.text.contains("Café preference"))
        XCTAssertFalse(result.text.contains("Gaming keyboard"))
        XCTAssertEqual(result.includedCount, 1)
        XCTAssertTrue(result.truncated)
    }
    func testFallbackUsesRecencyAndStableInputOrderForTies() {
        let date = Date(timeIntervalSince1970: 10)
        let notes = [MemoryNote(content: "First tied note", createdAt: date), MemoryNote(content: "Older note", createdAt: Date(timeIntervalSince1970: 1)), MemoryNote(content: "Second tied note", createdAt: date)]
        let result = MemoryContextBuilder.build(notes: notes, query: "unmatched", maximumNotes: 2)
        XCTAssertTrue(result.text.contains("First tied note"))
        XCTAssertTrue(result.text.contains("Second tied note"))
        XCTAssertFalse(result.text.contains("Older note"))
        XCTAssertLessThan(result.text.range(of: "First tied note")!.lowerBound, result.text.range(of: "Second tied note")!.lowerBound)
    }
    func testSelectionNeverMutatesSavedNotes() {
        let notes = [MemoryNote(content: String(repeating: "long note ", count: 2000))]
        let before = notes
        _ = MemoryContextBuilder.build(notes: notes, query: "note", maximumBytes: 128)
        XCTAssertEqual(notes, before)
    }
    func testFullLibraryScanAndQueryCapAreDisclosed() {
        let notes = (0..<501).map { MemoryNote(content: $0 == 500 ? "unscannedneedle" : "plain \($0)") }
        let result = MemoryContextBuilder.build(notes: notes, query: "unscannedneedle " + String(repeating: "x", count: 5000))
        XCTAssertEqual(result.scannedCount, 501)
        XCTAssertEqual(result.totalCount, 501)
        XCTAssertFalse(result.scanLimited)
        XCTAssertTrue(result.queryTruncated)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.text.contains("unscannedneedle"))
    }
    func testRelevantPassageNearEndSurvivesExcerptBudget() {
        let text = String(repeating: "unrelated context ", count: 140) + "My passport appointment is Tuesday at noon."
        let result = MemoryContextBuilder.build(notes: [MemoryNote(content: text)], query: "passport", maximumBytes: 512)
        XCTAssertTrue(result.text.contains("passport appointment is Tuesday at noon."))
        XCTAssertLessThanOrEqual(result.text.utf8.count, 512)
        XCTAssertEqual(result.includedCount, 1)
        XCTAssertTrue(result.truncated)
    }
    func testUnicodeMatchingPassagePreservesOriginalScalarsAndWholeWordRelevance() {
        let text = "cafeteria " + String(repeating: "日本語🦉 ", count: 150) + "Cafe\u{301} preference: oat milk."
        let result = MemoryContextBuilder.build(notes: [MemoryNote(content: text)], query: "CAFE", maximumBytes: 300)
        XCTAssertTrue(result.text.contains("Cafe\u{301} preference: oat milk."))
        XCTAssertFalse(result.text.contains("cafeteria"))
        XCTAssertLessThanOrEqual(result.text.utf8.count, 300)
        let excerpt = result.text.components(separatedBy: "\n- ").last!
        XCTAssertNotNil(Data(text.utf8).range(of: Data(excerpt.utf8)), "The excerpt must be byte-exact contiguous source text")
        XCTAssertTrue(result.truncated)
    }
    func testEmptyInputProducesNoDisclaimer() {
        let result = MemoryContextBuilder.build(notes: [], query: "hello")
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.includedCount, 0)
        XCTAssertFalse(result.truncated)
    }
    func testHugeCallerLimitsCannotExpandBuiltInCaps() {
        let notes = (0..<20).map { MemoryNote(content: String(repeating: "x", count: 5000), createdAt: Date(timeIntervalSince1970: Double($0))) }
        let result = MemoryContextBuilder.build(notes: notes, query: "x", maximumBytes: Int.max, maximumNotes: Int.max)
        XCTAssertLessThanOrEqual(result.text.utf8.count, 1024)
        XCTAssertLessThanOrEqual(result.includedCount, 8)
    }
}
