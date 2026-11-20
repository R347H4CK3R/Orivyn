import XCTest
@testable import JarvisEVO

@MainActor
final class WebBrowserExtrasTests: XCTestCase {
    func testNormalNavigationAndSearchNeverRequestReader() throws {
        for input in ["https://example.com/article", "an ordinary search"] {
            XCTAssertFalse(try BrowserPresentation.validated(input).prefersReader)
        }
    }
    func testReaderRequiresExplicitChoiceAndVerifiedWebsite() throws {
        let reader = try BrowserPresentation.validated(" https://example.com/article?x=1 ", reader: true)
        XCTAssertTrue(reader.prefersReader)
        XCTAssertEqual(reader.destination.url.absoluteString, "https://example.com/article?x=1")
        for input in ["search words", "http://example.com", "https://user:secret@example.com", "javascript:alert(1)"] {
            XCTAssertThrowsError(try BrowserPresentation.validated(input, reader: true))
        }
    }
    func testCleanLinkRemovesOnlyKnownTrackingKeysPreservingFunctionalBytes() throws {
        XCTAssertEqual(try WebCleanLink.validated("https://example.com/watch?v=abc&t=30&utm_source=share#details"), "https://example.com/watch?v=abc&t=30#details")
        for unchanged in ["https://example.com/watch?v=abc&t=30#details", "https://example.com/?q=a+b&x=%2f&&flag=&unknown=%26#x%2fy", "https://example.com/?", "https://example.com/?utm_custom=keep#fragment"] {
            XCTAssertEqual(try WebCleanLink.validated(unchanged), unchanged)
        }
        XCTAssertEqual(try WebCleanLink.validated("https://example.com/?q=a+b&utm_medium=social&&x=%2f#part"), "https://example.com/?q=a+b&&x=%2f#part")
        XCTAssertEqual(try WebCleanLink.validated("https://example.com/?utm_source=s&fbclid=123#part"), "https://example.com/#part")
        XCTAssertEqual(try WebCleanLink.validated("https://example.com/?%75tm_source=x&v=abc"), "https://example.com/?v=abc")
        XCTAssertThrowsError(try WebCleanLink.validated("https://user:secret@example.com"))
        // Bookmark behavior is intentionally separate and unchanged.
        XCTAssertEqual(try WebBookmarkStore.bookmarkAddress("https://example.com/watch?v=abc#part"), "https://example.com/watch")
    }
}
