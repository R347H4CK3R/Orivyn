import XCTest
@testable import JarvisEVO
final class LocalConversationSearchTests: XCTestCase {
    private func conversation(name: String = "document.pdf", text: String? = "The launch code is ORCHID", media: String = "application/pdf") -> Conversation {
        Conversation(title: "Unrelated", messages: [ChatMessage(role: .user, content: "Read this", attachments: [ChatAttachment(name: name, relativePath: "private-path", mediaType: media, byteCount: 1, extractedText: text)])])
    }
    func testDocumentOnlyFactUsesStoredTextWithEvidenceSource() throws {
        let c = conversation()
        let r = try LocalConversationSearch.search(conversations: [c], query: "orchid", limit: 10)
        XCTAssertEqual(r.matches.count, 1); XCTAssertEqual(r.matches.first?.evidenceSource, "attachment_text")
        XCTAssertTrue(r.matches.first?.excerpt.contains("ORCHID") == true); XCTAssertEqual(r.matches.first?.id, c.id)
    }
    func testImageOCRIsStoredTextNotVisualUnderstanding() throws {
        let r = try LocalConversationSearch.search(conversations: [conversation(text: "STOP sign", media: "image/png")], query: "stop", limit: 1)
        XCTAssertEqual(r.matches.first?.evidenceSource, "attachment_text"); XCTAssertEqual(r.matches.first?.excerpt, "STOP sign")
    }
    func testAttachmentNameMatchesAndMissingTextInventsNothing() throws {
        let c = conversation(name: "orchid.pdf", text: nil)
        let r = try LocalConversationSearch.search(conversations: [c], query: "orchid", limit: 10)
        XCTAssertEqual(r.matches.first?.evidenceSource, "attachment_name"); XCTAssertEqual(r.matches.first?.excerpt, "orchid.pdf")
        XCTAssertTrue(try LocalConversationSearch.search(conversations: [c], query: "launch", limit: 10).matches.isEmpty)
        XCTAssertTrue(try LocalConversationSearch.search(conversations: [c], query: "private-path", limit: 10).matches.isEmpty)
    }
    func testExistingMessagePreferenceIncludingFailedMessagesIsPreserved() throws {
        let c = Conversation(title: "orchid title", messages: [ChatMessage(role: .assistant, content: "orchid partial", state: .failed)])
        let r = try LocalConversationSearch.search(conversations: [c], query: "orchid", limit: 1)
        XCTAssertEqual(r.matches.first?.evidenceSource, "message"); XCTAssertEqual(r.matches.first?.excerpt, "orchid partial")
        XCTAssertEqual(try LocalConversationSearch.search(conversations: [Conversation(title: "orchid title")], query: "orchid", limit: 1).matches.first?.evidenceSource, "title")
    }
    func testBoundsOrderAndImmutableLongUnicodeEvidence() throws {
        let c = conversation(text: String(repeating: "😀", count: 100) + " ORCHID " + String(repeating: "😀", count: 100))
        let original = c
        let r = try LocalConversationSearch.search(conversations: [c,c,c], query: "orchid", limit: 2)
        XCTAssertEqual(r.matches.count, 2); XCTAssertEqual(r.searchedConversations, 3); XCTAssertFalse(r.searchLimited)
        XCTAssertEqual(r.totalMatchesInWindow, 3); XCTAssertTrue(r.resultsLimited)
        XCTAssertLessThanOrEqual(r.matches[0].excerpt.utf8.count, 160); XCTAssertTrue(r.matches[0].excerpt.contains("ORCHID")); XCTAssertTrue(r.matches[0].excerptMayBeTruncated)
        XCTAssertEqual(c, original)
        let limited = try LocalConversationSearch.search(conversations: Array(repeating: Conversation(), count: 500) + [c], query: "orchid", limit: 10)
        XCTAssertTrue(limited.matches.isEmpty); XCTAssertEqual(limited.searchedConversations, 500); XCTAssertTrue(limited.searchLimited)
    }
    func testInvalidQueryAndLimitFailClosed() {
        for query in ["", " \n", String(repeating: "a", count: 257)] { XCTAssertThrowsError(try LocalConversationSearch.search(conversations: [], query: query, limit: 1)) }
        for limit in [0,11] { XCTAssertThrowsError(try LocalConversationSearch.search(conversations: [], query: "x", limit: limit)) }
    }
}
