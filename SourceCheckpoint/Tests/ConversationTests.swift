import XCTest
@testable import JarvisEVO

final class ConversationTests: XCTestCase {
    func testBranchRetainsMessagesOnlyThroughSelectedMessageAndUsesNewIdentity() throws {
        let first = ChatMessage(role: .user, content: "One")
        let second = ChatMessage(role: .assistant, content: "Two")
        let original = Conversation(title: "Original", messages: [first, second])
        let branch = try original.branching(through: first.id)
        XCTAssertNotEqual(branch.id, original.id)
        XCTAssertEqual(branch.messages.map(\.content), ["One"])
        XCTAssertEqual(original.messages.count, 2)
    }
    func testEditingUserMessageInvalidatesOnlySubsequentHistory() throws {
        let first = ChatMessage(role: .user, content: "Original")
        var conversation = Conversation(messages: [first, ChatMessage(role: .assistant, content: "Old answer")])
        try conversation.editUserMessage(id: first.id, content: "Revised")
        XCTAssertEqual(conversation.messages.map(\.content), ["Revised"])
    }
    func testEditingAssistantMessageIsRejected() {
        let message = ChatMessage(role: .assistant, content: "Response")
        var conversation = Conversation(messages: [message])
        XCTAssertThrowsError(try conversation.editUserMessage(id: message.id, content: "Changed"))
        XCTAssertEqual(conversation.messages[0].content, "Response")
    }
    func testEmptyEditIsRejectedWithoutMutatingHistory() {
        let message = ChatMessage(role: .user, content: "Keep")
        var conversation = Conversation(messages: [message])
        XCTAssertThrowsError(try conversation.editUserMessage(id: message.id, content: "   "))
        XCTAssertEqual(conversation.messages[0].content, "Keep")
    }
    func testOversizedLatestTurnIsRejectedInsteadOfDiscarded() {
        XCTAssertThrowsError(try ContextWindow.trim([ChatMessage(role: .user, content: String(repeating: "x", count: 901))], characterBudget: 900))
    }
    func testAttachmentTextParticipatesInContextBudget() {
        let file = ChatAttachment(name: "Data", relativePath: "Attachments/data.txt", mediaType: "text/plain", byteCount: 1000, extractedText: String(repeating: "x", count: 1000))
        XCTAssertThrowsError(try ContextWindow.trim([ChatMessage(role: .user, content: "Read this", attachments: [file])], characterBudget: 900))
    }
    func testContextKeepsSystemAndNewestWholeMessagesWithinBudget() throws {
        let messages = (0..<10).map { ChatMessage(role: $0 % 2 == 0 ? .user : .assistant, content: String(repeating: "x", count: 400)) }
        let trimmed = try ContextWindow.trim(messages, characterBudget: 900)
        XCTAssertEqual(trimmed.count, 2)
        XCTAssertEqual(trimmed.last?.id, messages.last?.id)
    }
}
