import XCTest
@testable import JarvisEVO

final class MemorySearchTests: XCTestCase {
    func testLiteralSearchPreservesIDsOrderAndRequiresEveryTerm() {
        let first = MemoryNote(content: "Café: prefer metric units")
        let second = MemoryNote(content: "Gaming laptop")
        let third = MemoryNote(content: "Metric measurements")
        let notes = [first, second, third]
        XCTAssertEqual(MemorySearch.matches(notes, query: "CAFE metric").map(\.id), [first.id])
        XCTAssertEqual(MemorySearch.matches(notes, query: "metric").map(\.id), [first.id, third.id])
        XCTAssertEqual(MemorySearch.matches(notes, query: " "), notes)
        XCTAssertTrue(MemorySearch.matches(notes, query: ".*").isEmpty)
        XCTAssertTrue(MemorySearch.matches(notes, query: String(repeating: "x", count: 1025)).isEmpty)
    }
    func testFullLibraryPhraseSearchRetainsOnlyBoundedResults() throws {
        let notes = (0..<10_000).map { MemoryNote(content: $0 < 9000 ? "ordinary note" : "Café preference \($0)") }
        let start = Date()
        let result = try MemorySearch.phrase(notes, query: "cafe", limit: 3)
        XCTAssertEqual(result.notes.map(\.id), Array(notes[9000..<9003]).map(\.id))
        XCTAssertEqual(result.matchCount, 1000)
        XCTAssertEqual(result.scannedCount, 10_000)
        // Generous regression ceiling, not a device responsiveness guarantee.
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }
    func testFullLibraryContextFindsLateNoteWithoutUnboundedOutput() {
        let notes = (0..<10_000).map { MemoryNote(content: $0 == 9999 ? "needle preference" : "ordinary note") }
        let start = Date()
        let result = MemoryContextBuilder.build(notes: notes, query: "needle", maximumNotes: 1)
        XCTAssertTrue(result.text.contains("needle preference"))
        XCTAssertEqual(result.scannedCount, 10_000)
        XCTAssertFalse(result.scanLimited)
        XCTAssertLessThanOrEqual(result.text.utf8.count, 1024)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }
    func testPageSearchScansBeyond500ButReturnsOnlyRequestedPage() throws {
        let notes = (0..<1200).map { MemoryNote(content: "Café item \($0)") }
        let page = try MemorySearch.page(notes, query: "cafe", offset: 1000, limit: 100)
        XCTAssertEqual(page.totalMatches, 1200)
        XCTAssertEqual(page.notes.count, 100)
        XCTAssertEqual(page.notes.first?.id, notes[1000].id)
        XCTAssertThrowsError(try MemorySearch.page(notes, query: "cafe", offset: -1, limit: 100))
        XCTAssertThrowsError(try MemorySearch.page(notes, query: "cafe", offset: 0, limit: 201))
        XCTAssertEqual(try MemorySearch.page(notes, query: "absent", offset: 0).notes.count, 0)
    }
    @MainActor
    func testCancelledPageDoesNotReturnAStaleResult() async throws {
        let work = Task {
            return try await MemorySearch.pageAsync([MemoryNote(content: "old")], query: "old", offset: 0)
        }
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled search returned") } catch is CancellationError { }
    }

}
