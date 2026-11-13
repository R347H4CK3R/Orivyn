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
}
