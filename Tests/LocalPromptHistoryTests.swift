import XCTest
@testable import JarvisEVO

final class LocalPromptHistoryTests: XCTestCase {
    func testFittingRestoredHistoryDropsOrphanAnswerBeforeCountingTokens() throws {
        let entries = [LocalPromptMessage(role: "assistant", content: "Unattributed old answer"),
                       LocalPromptMessage(role: "user", content: "Current question")]
        let selected = try LocalPromptBuilder.trimToFit(entries, maxTokens: 10, contextSize: 100) { messages in
            XCTAssertEqual(messages.map(\.role), ["user"])
            return messages.reduce(0) { $0 + $1.content.count }
        }
        XCTAssertEqual(selected.map(\.content), ["Current question"])
    }

    func testFailedFirstUserCannotLeaveAnswerAttachedToCurrentQuestion() throws {
        let file = ChatAttachment(name: "notes.txt", relativePath: "notes.txt", mediaType: "text/plain", byteCount: 5, extractedText: "notes")
        let source = [ChatMessage(role: .user, content: "Unavailable question", state: .failed),
                      ChatMessage(role: .assistant, content: "Unattributed answer"),
                      ChatMessage(role: .user, content: "", attachments: [file])]
        let selected = try LocalPromptBuilder.prepareMessages(from: source, maxTokens: 10, contextSize: 1000) { $0.reduce(0) { $0 + $1.content.count } }
        XCTAssertEqual(selected.map(\.role), ["user"])
        XCTAssertTrue(selected.last?.content.contains("notes") == true)
        XCTAssertEqual(source[2].attachments, [file])
    }

    func testOrphanRemovalPreservesSystemMessagesAndCompleteFollowingTurns() throws {
        let entries = [LocalPromptMessage(role: "system", content: "Keep this context"),
                       LocalPromptMessage(role: "assistant", content: "Orphan one"),
                       LocalPromptMessage(role: "system", content: "More context"),
                       LocalPromptMessage(role: "assistant", content: "Orphan two"),
                       LocalPromptMessage(role: "user", content: "Earlier question"),
                       LocalPromptMessage(role: "assistant", content: "Paired answer"),
                       LocalPromptMessage(role: "user", content: "Current question")]
        let selected = try LocalPromptBuilder.trimToFit(entries, maxTokens: 10, contextSize: 1000) { $0.reduce(0) { $0 + $1.content.count } }
        XCTAssertEqual(selected.map(\.content), ["Keep this context", "More context", "Earlier question", "Paired answer", "Current question"])
    }

    func testTrimmingPastQuestionDropsAnswerSeparatedBySystemEntry() throws {
        let entries = [LocalPromptMessage(role: "user", content: String(repeating: "x", count: 100)),
                       LocalPromptMessage(role: "system", content: "Keep"),
                       LocalPromptMessage(role: "assistant", content: "Orphan"),
                       LocalPromptMessage(role: "user", content: "Now")]
        let selected = try LocalPromptBuilder.trimToFit(entries, maxTokens: 10, contextSize: 30) { $0.reduce(0) { $0 + $1.content.count } }
        XCTAssertEqual(selected.map(\.content), ["Keep", "Now"])
    }

    func testValidHistoryIsUnchangedWhenItFits() throws {
        let entries = [LocalPromptMessage(role: "system", content: "Context"),
                       LocalPromptMessage(role: "user", content: "Question"),
                       LocalPromptMessage(role: "assistant", content: "Answer"),
                       LocalPromptMessage(role: "user", content: "Follow-up")]
        let selected = try LocalPromptBuilder.trimToFit(entries, maxTokens: 10, contextSize: 1000) { $0.reduce(0) { $0 + $1.content.count } }
        XCTAssertEqual(selected.map(\.role), entries.map(\.role))
        XCTAssertEqual(selected.map(\.content), entries.map(\.content))
    }

    func testOrphanRemovalDoesNotAllowOversizedCurrentQuestionToBeCut() {
        let question = String(repeating: "Keep my full question. ", count: 100)
        XCTAssertThrowsError(try LocalPromptBuilder.trimToFit([
            LocalPromptMessage(role: "assistant", content: "Orphan"),
            LocalPromptMessage(role: "user", content: question)
        ], maxTokens: 10, contextSize: 100) { entries in
            XCTAssertEqual(entries.last?.content, question)
            return entries.reduce(0) { $0 + $1.content.count }
        }) { XCTAssertEqual($0 as? LocalModelError, .promptTooLong) }
    }

    func testAssistantOnlyInputStillFailsInsteadOfCreatingQuestion() {
        XCTAssertThrowsError(try LocalPromptBuilder.trimToFit([LocalPromptMessage(role: "assistant", content: "Orphan")], maxTokens: 10, contextSize: 100) { _ in 1 })
    }
}
