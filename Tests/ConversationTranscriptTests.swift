import XCTest
@testable import JarvisEVO

final class ConversationTranscriptTests: XCTestCase {
    func testRolesAndVisibleTextArePreservedWithoutMislabelingSystem() {
        let c = Conversation(title: "Session", messages: [ChatMessage(role: .user, content: "  hello\nworld  "), ChatMessage(role: .assistant, content: "answer"), ChatMessage(role: .system, content: "system text")])
        let text = ConversationTranscript.markdown(c)
        XCTAssertTrue(text.contains("## You\n\n  hello\nworld  "))
        XCTAssertTrue(text.contains("## Jarvis\n\nanswer"))
        XCTAssertTrue(text.contains("## System\n\nsystem text"))
    }
    func testIncompleteStatesAreExplicitAndKeepPartialText() {
        for (state,label) in [(MessageState.streaming,"Streaming — incomplete"),(.interrupted,"Interrupted — incomplete"),(.failed,"Failed — incomplete")] {
            let text = ConversationTranscript.markdown(Conversation(messages: [ChatMessage(role: .assistant, content: "partial output", state: state)]))
            XCTAssertTrue(text.contains(label)); XCTAssertTrue(text.contains("partial output"))
        }
    }
    func testAttachmentNamesIncludedButNotContentsPathsOrIdentifiers() {
        let a = ChatAttachment(name: "report.pdf", relativePath: "private-storage-path", mediaType: "application/pdf", byteCount: 100, extractedText: "PRIVATE EXTRACTED TEXT", previewRelativePath: "private-preview")
        let c = Conversation(messages: [ChatMessage(role: .user, content: "read this", attachments: [a])])
        let text = ConversationTranscript.markdown(c)
        XCTAssertTrue(text.contains("report.pdf")); XCTAssertTrue(text.contains("Attachment contents and files are not included"))
        for hidden in [a.id.uuidString,a.relativePath,a.previewRelativePath!,a.extractedText!] { XCTAssertFalse(text.contains(hidden)) }
        XCTAssertEqual(c.messages[0].attachments[0], a)
    }
    func testAttachmentOnlyMessageAndEmptyConversationStillExport() {
        let a = ChatAttachment(name: "image.png", relativePath: "private.png", mediaType: "image/png", byteCount: 100)
        XCTAssertTrue(ConversationTranscript.markdown(Conversation(messages: [ChatMessage(role: .user, content: "", attachments: [a])])).contains("image.png"))
        XCTAssertEqual(ConversationTranscript.markdown(Conversation(title: "Empty")), "# Empty\n\n")
    }
    func testMetadataCannotCreateMarkdownHeadingsOrLinks() {
        let a = ChatAttachment(name: "file\n## fake [link](https://example.com)", relativePath: "private", mediaType: "text/plain", byteCount: 1)
        let text = ConversationTranscript.markdown(Conversation(title: "Title\n## forged", messages: [ChatMessage(role: .user, content: "**visible body**", attachments: [a])]))
        XCTAssertFalse(text.contains("\n## forged")); XCTAssertFalse(text.contains("\n## fake"))
        XCTAssertFalse(text.contains("[link](https://example.com)"))
        XCTAssertTrue(text.contains("**visible body**"))
    }

}
