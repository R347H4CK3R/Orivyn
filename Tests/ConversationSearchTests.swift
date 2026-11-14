import XCTest
@testable import JarvisEVO

final class ConversationSearchTests: XCTestCase {
    func testLiteralSearchIncludesExtractedFilesWithoutOpeningThem() {
        let file = ChatAttachment(name: "Café receipt.pdf", relativePath: "missing.pdf", mediaType: "application/pdf", byteCount: 100, extractedText: "Total: 42 apples")
        let conversation = Conversation(title: "Shopping", messages: [ChatMessage(role: .user, content: "Check this", attachments: [file])])
        XCTAssertTrue(ConversationSearch.matches(conversation, query: "CAFE"))
        XCTAssertTrue(ConversationSearch.matches(conversation, query: "42 apples"))
        XCTAssertTrue(ConversationSearch.matches(conversation, query: " shopping "))
        XCTAssertFalse(ConversationSearch.matches(conversation, query: ".*"))
        XCTAssertFalse(ConversationSearch.matches(conversation, query: String(repeating: "x", count: 1025)))
        XCTAssertTrue(ConversationSearch.matches(conversation, query: " "))
    }
}
