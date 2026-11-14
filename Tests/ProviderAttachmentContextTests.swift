import XCTest
@testable import JarvisEVO

final class ProviderAttachmentContextTests: XCTestCase {
    private func message(text: String?, image: Bool = false) -> ChatMessage {
        ChatMessage(role: .user, content: "", attachments: [ChatAttachment(name: "sample", relativePath: "sample.txt", mediaType: image ? "image/png" : "text/plain", byteCount: 10, extractedText: text)])
    }
    func testUnavailableDocumentsAreExplicitForNilEmptyAndWhitespace() {
        for text: String? in [nil, "", " \n\t"] {
            let prompt = message(text: text).promptContent
            XCTAssertTrue(prompt.contains("No extracted text is available"))
            XCTAssertTrue(prompt.contains("Do not claim to have read"))
        }
    }
    func testEmptyImagesPreserveOCRBoundaryAndUnavailableNotice() {
        for text: String? in [nil, "", " \n"] {
            let prompt = message(text: text, image: true).promptContent
            XCTAssertTrue(prompt.contains(ImageOCRResult.textOnlyNotice))
            XCTAssertTrue(prompt.contains("No extracted text is available"))
        }
    }
    func testAttachmentOnlyImportedMessageIsKeptWithoutChangingSource() throws {
        let source = message(text: "visible saved text")
        let imported = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(source))
        let selected = try ContextWindow.trim([imported], characterBudget: 1000)
        XCTAssertEqual(selected, [source])
        XCTAssertTrue(selected.first?.promptContent.contains("visible saved text") == true)
    }
    func testWholeNewestAttachmentMessageFailsClosedWhenBudgetTooSmall() {
        let source = message(text: nil, image: true)
        XCTAssertThrowsError(try ContextWindow.trim([source], characterBudget: source.promptContent.count - 1))
        XCTAssertEqual(try ContextWindow.trim([source], characterBudget: source.promptContent.count), [source])
    }
    func testOlderMessagesAreDroppedWholeAndFailedMessagesExcluded() throws {
        let old = ChatMessage(role: .user, content: String(repeating: "x", count: 1000))
        let newest = message(text: "readable")
        var failed = message(text: "failed attachment"); failed.state = .failed
        XCTAssertEqual(try ContextWindow.trim([old, newest, failed], characterBudget: newest.promptContent.count), [newest])
    }
    func testTruncationDisclosedAndSourceRemainsIntact() {
        let source = message(text: String(repeating: "a", count: 20_001), image: true)
        let original = source
        let prompt = source.promptContent
        XCTAssertTrue(prompt.contains("Attachment text truncated"))
        XCTAssertTrue(prompt.contains(ImageOCRResult.textOnlyNotice))
        XCTAssertEqual(source, original)
        XCTAssertFalse(prompt.contains(String(repeating: "a", count: 20_001)))
    }
}
