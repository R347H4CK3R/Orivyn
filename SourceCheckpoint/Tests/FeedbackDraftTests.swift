import XCTest
@testable import JarvisEVO

final class FeedbackDraftTests: XCTestCase {
    func testGitHubDraftPreservesDestinationAndEncodesUserContent() throws {
        let draft = FeedbackDraft(title: "A & B # idea", details: "Keep this? x=y\nNo private data")
        let url = try draft.githubDraftURL(repository: "https://github.com/R347H4CK3R/Jarvis-EVO")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "github.com")
        XCTAssertEqual(parts.path, "/R347H4CK3R/Jarvis-EVO/issues/new")
        XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "title" })?.value, "A & B # idea")
        XCTAssertTrue(parts.queryItems?.first(where: { $0.name == "body" })?.value?.contains("Keep this? x=y") == true)
    }
    func testInvalidDestinationsAndBlankOrOversizedDraftAreRejected() {
        let draft = FeedbackDraft(title: "An idea", details: "A concrete improvement")
        for url in ["http://github.com/o/r", "https://github.com.evil.test/o/r", "https://user:secret@github.com/o/r", "https://github.com/o/r/issues", "https://github.com/o/r?target=other", "https://github.com:8443/o/r"] {
            XCTAssertThrowsError(try draft.githubDraftURL(repository: url), url)
        }
        XCTAssertThrowsError(try FeedbackDraft(title: " ", details: "Text").githubDraftURL(repository: "https://github.com/o/r"))
        XCTAssertThrowsError(try FeedbackDraft(title: "Title", details: String(repeating: "x", count: 4_001)).githubDraftURL(repository: "https://github.com/o/r"))
    }
    func testExportContainsOnlyEnteredFieldsAndAppName() {
        XCTAssertEqual(FeedbackDraft(title: "Better search", details: "Search offline.").exportText,
                       "# Orivyn suggestion: Better search\n\nSearch offline.\n")
    }
}
