import XCTest
@testable import JarvisEVO

final class LocalSearchExcerptTests: XCTestCase {
    func testLateMatchReturnsMatchingPassage() {
        let text = String(repeating: "a", count: 5000) + "IMPORTANT NEEDLE" + String(repeating: "b", count: 500)
        let result = LocalSearchExcerpt.excerpt(text: text, query: "needle")
        XCTAssertTrue(result.contains("NEEDLE"))
        XCTAssertLessThanOrEqual(result.utf8.count, 160)
        XCTAssertTrue(text.contains(result))
    }
    func testFoldedMatchPreservesOriginalAccentsAndCase() {
        let text = String(repeating: "x", count: 500) + "Café preference" + String(repeating: "y", count: 500)
        let result = LocalSearchExcerpt.excerpt(text: text, query: "CAFE")
        XCTAssertTrue(result.contains("Café"))
        XCTAssertTrue(text.contains(result))
    }
    func testMultibyteScalarSafetyAndTinyBudgets() {
        let text = "日本語🦉日本語"
        for budget in 0...20 {
            let result = LocalSearchExcerpt.excerpt(text: text, query: "🦉", maximumBytes: budget)
            XCTAssertLessThanOrEqual(result.utf8.count, budget)
            XCTAssertEqual(String(data: Data(result.utf8), encoding: .utf8), result)
            XCTAssertTrue(text.contains(result) || result.isEmpty)
        }
    }
    func testUnknownOrEmptyQueryFallsBackToPrefix() {
        XCTAssertEqual(LocalSearchExcerpt.excerpt(text: "abcdef", query: "missing", maximumBytes: 3), "abc")
        XCTAssertEqual(LocalSearchExcerpt.excerpt(text: "abcdef", query: "", maximumBytes: 3), "abc")
        XCTAssertEqual(LocalSearchExcerpt.excerpt(text: "", query: "anything"), "")
    }
    func testLongMatchStartsAtMatchAndTruncates() {
        let match = String(repeating: "q", count: 200)
        let result = LocalSearchExcerpt.excerpt(text: "prefix" + match + "suffix", query: match, maximumBytes: 20)
        XCTAssertEqual(result, String(repeating: "q", count: 20))
    }
    func testControlCharactersAreNotSilentlyReplaced() {
        let text = "before\u{0}needle\n\t\u{7}after"
        XCTAssertEqual(LocalSearchExcerpt.excerpt(text: text, query: "needle"), text)
    }
    func testTextThatFitsIsReturnedWholeEvenWhenMatchIsAtEnd() {
        let text = String(repeating: "x", count: 120) + "needle"
        XCTAssertEqual(LocalSearchExcerpt.excerpt(text: text, query: "needle"), text)
    }
    func testCallerCannotExpandHardByteCap() {
        let result = LocalSearchExcerpt.excerpt(text: String(repeating: "x", count: 1000), query: "x", maximumBytes: Int.max)
        XCTAssertEqual(result.utf8.count, 160)
        XCTAssertEqual(LocalSearchExcerpt.excerpt(text: "abc", query: "b", maximumBytes: -1), "")
    }
}
