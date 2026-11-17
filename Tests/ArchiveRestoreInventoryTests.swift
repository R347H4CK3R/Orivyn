import XCTest
@testable import JarvisEVO

final class ArchiveRestoreInventoryTests: XCTestCase {
    func testGroupsSafeLabelsInPlanOrderAndPagesAtFifty() throws {
        let messages = (0..<53).map { index in ChatMessage(id: UUID(), role: .user, content: "Hidden from inventory \(index)") }
        let conversation = Conversation(title: "Title\n" + String(repeating: "a", count: 250), messages: messages)
        let references = messages.reversed().flatMap { message in [
            ArchiveRestoreInventory.Reference(messageID: message.id, source: "attachmentMetadata"),
            .init(messageID: message.id, source: "contentPart"),
            .init(messageID: message.id, source: "https://untrusted.example/never-display") ] }
        let first = try ArchiveRestoreInventory.page(conversations: [conversation], references: references)
        XCTAssertEqual(first.totalMessages, 53); XCTAssertEqual(first.totalRecords, 159)
        XCTAssertEqual(first.entries.count, 50); XCTAssertEqual(first.nextOffset, 50); XCTAssertEqual(first.remaining, 3)
        XCTAssertEqual(first.entries.map(\.id), Array(messages.prefix(50)).map(\.id))
        let entry = try XCTUnwrap(first.entries.first)
        XCTAssertEqual(entry.conversationID, conversation.id); XCTAssertEqual(entry.messageIndex, 1)
        XCTAssertEqual(entry.title.count, 200); XCTAssertFalse(entry.title.contains("\n"))
        XCTAssertEqual(entry.totalRecords, 3); XCTAssertEqual(entry.contentPartCount, 1)
        XCTAssertEqual(entry.attachmentMetadataCount, 1); XCTAssertEqual(entry.otherCount, 1)
        let last = try ArchiveRestoreInventory.page(conversations: [conversation], references: references, offset: 50)
        XCTAssertEqual(last.entries.map(\.id), Array(messages.suffix(3)).map(\.id))
        XCTAssertNil(last.nextOffset); XCTAssertEqual(last.remaining, 0)
    }
    func testRejectsOrphansAndAmbiguousIDsRatherThanGuessing() throws {
        let message = ChatMessage(role: .user, content: "synthetic")
        let conversation = Conversation(messages: [message])
        XCTAssertThrowsError(try ArchiveRestoreInventory.page(conversations: [conversation], references: [.init(messageID: UUID(), source: "contentPart")]))
        XCTAssertThrowsError(try ArchiveRestoreInventory.page(conversations: [conversation, conversation], references: []))
        XCTAssertThrowsError(try ArchiveRestoreInventory.page(conversations: [conversation, Conversation(messages: [message])], references: []))
        XCTAssertThrowsError(try ArchiveRestoreInventory.page(conversations: [Conversation(messages: [message, message])], references: []))
    }
    func testEmptyInventoryAndOffsetValidation() throws {
        let empty = try ArchiveRestoreInventory.page(conversations: [], references: [])
        XCTAssertTrue(empty.entries.isEmpty); XCTAssertEqual(empty.totalRecords, 0); XCTAssertNil(empty.nextOffset)
        XCTAssertThrowsError(try ArchiveRestoreInventory.page(conversations: [], references: [], offset: -1))
        XCTAssertThrowsError(try ArchiveRestoreInventory.page(conversations: [], references: [], offset: 1))
    }
    func testDuplicateReferenceRecordsCountWithoutPretendingTheyAreDistinctFiles() throws {
        let message = ChatMessage(role: .user, content: "synthetic")
        let ref = ArchiveRestoreInventory.Reference(messageID: message.id, source: "contentPart")
        let page = try ArchiveRestoreInventory.page(conversations: [Conversation(messages: [message])], references: [ref, ref])
        XCTAssertEqual(page.entries.first?.totalRecords, 2)
        XCTAssertEqual(page.totalMessages, 1); XCTAssertEqual(page.totalRecords, 2)
    }
}
