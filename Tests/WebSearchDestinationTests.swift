import XCTest
@testable import JarvisEVO

final class WebSearchDestinationTests: XCTestCase {
    func testSearchAlwaysUsesFixedHTTPSOriginWithOneLosslessQuery() throws {
        for text in ["plumbing tips", "a&b=c#fragment", "café 東京", "https://evil.example/?q=one&x=two", "C++ + Swift", "%20"] {
            let target = try WebSearchDestination.validated(text)
            let parts = try XCTUnwrap(URLComponents(url: target.url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(parts.scheme, "https")
            XCTAssertEqual(parts.host, "duckduckgo.com")
            XCTAssertEqual(parts.path, "/")
            XCTAssertNil(parts.user); XCTAssertNil(parts.password); XCTAssertNil(parts.fragment)
            XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "q", value: text)])
            XCTAssertFalse(parts.percentEncodedQuery?.contains("+") ?? true)
        }
    }
    func testBlankControlsAndOversizeAreRejectedWithoutTruncation() throws {
        for text in ["", "   ", "secret\ntext", "line\u{2028}break", "x\0y", String(repeating: "x", count: 1025), String(repeating: "😀", count: 257)] {
            XCTAssertThrowsError(try WebSearchDestination.validated(text))
        }
        let text = String(repeating: "😀", count: 256)
        let target = try WebSearchDestination.validated(text)
        XCTAssertEqual(URLComponents(url: target.url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, text)
        XCTAssertEqual(URLComponents(url: try WebSearchDestination.validated("  hello  ").url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "hello")
    }
    func testCombinedInputTrimsBeforeSchemeClassificationWithoutSearchingSecrets() throws {
        for prefix in [" ", "\t", "\n", "\u{00a0}"] {
            let target = try WebNavigationDraft.validated(prefix + "https://example.com/reset?token=synthetic" + "  ")
            XCTAssertTrue(target.isWebsite)
            XCTAssertEqual(target.destination.url.host, "example.com")
            XCTAssertEqual(target.destination.url.query, "token=synthetic")
            for unsafe in ["http://example.com/reset?token=synthetic", "javascript:alert(1)", "https://user:secret@example.com", "https://user%3Asecret@example.com"] {
                XCTAssertThrowsError(try WebNavigationDraft.validated(prefix + unsafe + " "))
            }
        }
    }

    func testWebsiteValidationIsStillStrict() {
        for address in ["http://example.com", "https://user:password@example.com", "javascript:alert(1)", "https://example.com:8080", "https://example.com/a b"] {
            XCTAssertThrowsError(try BrowserDestination.validated(address))
        }
        XCTAssertNoThrow(try BrowserDestination.validated("https://example.com/page?q=test"))
    }
}

@MainActor
final class WebBookmarkTests: XCTestCase {
    func testBookmarksRequireExplicitSaveAndNeverKeepQueryOrFragment() throws {
        let suite = "Orivyn.WebBookmarks.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WebBookmarkStore(defaults: defaults)
        let draft = try WebNavigationDraft.validated("https://example.com/article?token=synthetic#private")
        XCTAssertTrue(store.bookmarks.isEmpty)
        XCTAssertEqual(draft.destination.url.host, "example.com")
        try store.saveWebsite("https://example.com/article?token=synthetic#private")
        XCTAssertEqual(store.bookmarks, ["https://example.com/article"])
        try store.saveWebsite("https://example.com/article?other=1")
        XCTAssertEqual(store.bookmarks.count, 1)
        let restored = WebBookmarkStore(defaults: defaults)
        XCTAssertEqual(restored.bookmarks, store.bookmarks)
        restored.remove("https://example.com/article")
        XCTAssertTrue(WebBookmarkStore(defaults: defaults).bookmarks.isEmpty)
        XCTAssertThrowsError(try store.saveWebsite("https://user:secret@example.com"))
        XCTAssertThrowsError(try store.saveWebsite("words to search"))
    }
    func testCombinedFieldShowsSearchOrWebsiteWithoutPerformingNetwork() throws {
        XCTAssertEqual(try WebNavigationDraft.validated("a & b").actionTitle, "Search DuckDuckGo")
        XCTAssertEqual(try WebNavigationDraft.validated("https://example.com/").actionTitle, "Open website")
        XCTAssertThrowsError(try WebNavigationDraft.validated("http://example.com"))
        XCTAssertThrowsError(try WebNavigationDraft.validated("javascript:alert(1)"))
    }
}
