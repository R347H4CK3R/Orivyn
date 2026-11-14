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
    func testContextTrimmingDoesNotKeepAnAnswerWithoutItsQuestion() throws {
        let oldUser = ChatMessage(role: .user, content: String(repeating: "q", count: 100))
        let oldAnswer = ChatMessage(role: .assistant, content: "Unrelated old answer")
        let latest = ChatMessage(role: .user, content: "My current question")
        let original = [oldUser, oldAnswer, latest]
        let selected = try ContextWindow.trim(original, characterBudget: oldAnswer.promptContent.count + latest.promptContent.count)
        XCTAssertEqual(selected, [latest])
        XCTAssertEqual(original, [oldUser, oldAnswer, latest])
    }

    func testContextTrimmingKeepsWholeRecentTurnsAndLatestAttachment() throws {
        let oldUser = ChatMessage(role: .user, content: String(repeating: "q", count: 200))
        let orphan = ChatMessage(role: .assistant, content: "Old answer")
        let recentUser = ChatMessage(role: .user, content: "Recent question")
        let recentAnswer = ChatMessage(role: .assistant, content: "Recent answer")
        let attachment = ChatAttachment(name: "notes.txt", relativePath: "notes.txt", mediaType: "text/plain", byteCount: 8, extractedText: "Read me!")
        let latest = ChatMessage(role: .user, content: "", attachments: [attachment])
        let suffix = [orphan, recentUser, recentAnswer, latest]
        let selected = try ContextWindow.trim([oldUser] + suffix, characterBudget: suffix.reduce(0) { $0 + $1.promptContent.count })
        XCTAssertEqual(selected, [recentUser, recentAnswer, latest])
        XCTAssertEqual(selected.last?.attachments, [attachment])
    }

    func testContextTrimmingDoesNotLetSystemMessageHideOrphanedAnswers() throws {
        let oldUser = ChatMessage(role: .user, content: String(repeating: "q", count: 100))
        let system = ChatMessage(role: .system, content: "Context note")
        let orphan = ChatMessage(role: .assistant, content: "Old answer")
        let latest = ChatMessage(role: .user, content: "New question")
        let suffix = [system, orphan, latest]
        XCTAssertEqual(try ContextWindow.trim([oldUser] + suffix, characterBudget: suffix.reduce(0) { $0 + $1.promptContent.count }), [system, latest])
    }

    func testContextRejectsBudgetThatKeepsOnlyAnswerButDropsLatestUser() {
        let latest = ChatMessage(role: .user, content: String(repeating: "q", count: 100))
        let answer = ChatMessage(role: .assistant, content: "Answer")
        XCTAssertThrowsError(try ContextWindow.trim([latest, answer], characterBudget: answer.promptContent.count))
    }

    func testContextKeepsExactFullHistoryAndSystemMetadataWhenItFits() throws {
        let original = [ChatMessage(role: .system, content: "System context"), ChatMessage(role: .user, content: "Question"), ChatMessage(role: .assistant, content: "Answer"), ChatMessage(role: .user, content: "Next")]
        let budget = original.reduce(0) { $0 + $1.promptContent.count }
        XCTAssertEqual(try ContextWindow.trim(original, characterBudget: budget), original)
    }

    func testContextDropsAllLeadingAssistantFragmentsAfterTrimming() throws {
        let oldUser = ChatMessage(role: .user, content: String(repeating: "q", count: 100))
        let fragments = [ChatMessage(role: .assistant, content: "Part one"), ChatMessage(role: .assistant, content: "Part two", state: .interrupted)]
        let latest = ChatMessage(role: .user, content: "Current request")
        let suffix = fragments + [latest]
        XCTAssertEqual(try ContextWindow.trim([oldUser] + suffix, characterBudget: suffix.reduce(0) { $0 + $1.promptContent.count }), [latest])
    }

    func testFailedOrEmptyUserDoesNotAnchorLeadingAssistantAnswer() throws {
        for excluded in [ChatMessage(role: .user, content: "Failed", state: .failed), ChatMessage(role: .user, content: "")] {
            let answer = ChatMessage(role: .assistant, content: "Unanchored answer")
            let newest = ChatMessage(role: .user, content: "Current question")
            XCTAssertEqual(try ContextWindow.trim([excluded, answer, newest], characterBudget: 1000), [newest])
        }
    }

    func testAssistantOnlyInputProducesNoFalseUserContext() throws {
        let system = ChatMessage(role: .system, content: "System context")
        let answer = ChatMessage(role: .assistant, content: "Unanchored answer")
        XCTAssertEqual(try ContextWindow.trim([answer], characterBudget: 1000), [])
        XCTAssertEqual(try ContextWindow.trim([system, answer], characterBudget: 1000), [system])
        XCTAssertEqual(try ContextWindow.trim([], characterBudget: 1000), [])
    }

}
