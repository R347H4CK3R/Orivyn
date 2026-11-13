import XCTest
@testable import JarvisEVO

final class AttachmentPromptAvailabilityTests: XCTestCase {
    func testMissingDocumentTextIsExplicitAndDoesNotImplyFileWasRead() {
        let file = ChatAttachment(name: "unread.pdf", relativePath: "unread.pdf", mediaType: "application/pdf", byteCount: 50)
        let result = LocalPromptBuilder.messages(from: [ChatMessage(role: .user, content: "Summarize the document", attachments: [file])])[0].content
        XCTAssertTrue(result.hasPrefix("Summarize the document"))
        XCTAssertTrue(result.contains("1 attachment(s) have no extracted text"))
        XCTAssertTrue(result.contains("Do not claim to have read"))
    }

    func testEmptyImageHasExplicitTextOnlyLimitationEvenWhenBudgetIsZero() {
        let image = ChatAttachment(name: "photo.png", relativePath: "photo.png", mediaType: "image/png", byteCount: 50, extractedText: "")
        let result = LocalPromptBuilder.messages(from: [ChatMessage(role: .user, content: "Describe this", attachments: [image])], attachmentCharacterLimit: 0)[0].content
        XCTAssertTrue(result.contains(ImageOCRResult.textOnlyNotice))
        XCTAssertTrue(result.contains("1 attachment(s) have no extracted text"))
    }

    func testImageNoticeSurvivesSmallExcerptBudgetWithoutChangingSource() {
        let image = ChatAttachment(name: "photo.png", relativePath: "photo.png", mediaType: "image/png", byteCount: 50, extractedText: "EXIT")
        let source = [ChatMessage(role: .user, content: "Read the sign", attachments: [image])]
        let result = LocalPromptBuilder.messages(from: source, attachmentCharacterLimit: 1)[0].content
        XCTAssertTrue(result.contains(ImageOCRResult.textOnlyNotice))
        XCTAssertTrue(result.contains("text truncated"))
        XCTAssertEqual(source[0].attachments[0].extractedText, "EXIT")
    }
}
