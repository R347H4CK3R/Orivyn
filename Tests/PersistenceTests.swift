import XCTest
@testable import JarvisEVO

final class PersistenceTests: XCTestCase {
    func testHistorySurvivesReopenAndSearchFindsMessageContent() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try SQLiteConversationStore(url: url)
        let conversation = Conversation(title: "Saved", messages: [ChatMessage(role: .user, content: "Unique kiwi")])
        try await first.save(conversation)
        let reopened = try SQLiteConversationStore(url: url)
        let loaded = try await reopened.load(id: conversation.id)
        XCTAssertEqual(loaded?.messages.first?.content, "Unique kiwi")
        let results = try await reopened.list(query: "kiwi")
        XCTAssertEqual(results.map(\.id), [conversation.id])
    }
    func testInterruptedStreamIsRecoveredButCompletedMessageIsUntouched() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let first = try SQLiteConversationStore(url: url)
        let value = Conversation(messages: [ChatMessage(role: .user, content: "Hello"), ChatMessage(role: .assistant, content: "Partial", state: .streaming)])
        try await first.save(value)
        let reopened = try SQLiteConversationStore(url: url)
        let loaded = try await reopened.load(id: value.id)
        XCTAssertEqual(loaded?.messages[0].state, .complete)
        XCTAssertEqual(loaded?.messages[1].state, .interrupted)
        XCTAssertEqual(loaded?.messages[1].content, "Partial")
    }
    func testArchiveIsExcludedByDefaultAndIncludedExplicitly() async throws {
        let store = try SQLiteConversationStore(url: temporaryDatabase())
        var value = Conversation(title: "Archived")
        value.isArchived = true
        try await store.save(value)
        let visible = try await store.list()
        let all = try await store.list(includeArchived: true)
        XCTAssertTrue(visible.isEmpty)
        XCTAssertEqual(all.count, 1)
    }
    func testExportImportRoundTripAndMalformedImportDoesNotEraseData() async throws {
        let first = try SQLiteConversationStore(url: temporaryDatabase())
        let second = try SQLiteConversationStore(url: temporaryDatabase())
        let value = Conversation(title: "Backup", messages: [ChatMessage(role: .user, content: "Restorable")])
        try await first.save(value)
        let data = try await first.exportData()
        try await second.importData(data)
        let restored = try await second.load(id: value.id)
        XCTAssertEqual(restored, value)
        do { try await second.importData(Data("not-json".utf8)); XCTFail("Malformed import accepted") } catch { }
        let remaining = try await second.list()
        XCTAssertEqual(remaining.count, 1)
    }
    func testExportLargerThanTwentyMegabytesRemainsRestorable() async throws {
        let first = try SQLiteConversationStore(url: temporaryDatabase())
        let second = try SQLiteConversationStore(url: temporaryDatabase())
        let content = String(repeating: "x", count: 1_000_000)
        let value = Conversation(messages: (0..<21).map { _ in ChatMessage(role: .user, content: content) })
        try await first.save(value)
        let data = try await first.exportData()
        XCTAssertGreaterThan(data.count, 20 * 1024 * 1024)
        XCTAssertLessThanOrEqual(data.count, ConversationBackup.maximumBytes)
        try await second.importData(data)
        let restored = try await second.load(id: value.id)
        XCTAssertEqual(restored?.messages.count, 21)
        XCTAssertEqual(restored?.messages.last?.content.count, content.count)
    }
    func testOversizedBackupIsRejectedWithoutErasingExistingHistory() async throws {
        let store = try SQLiteConversationStore(url: temporaryDatabase())
        let value = Conversation(title: "Keep")
        try await store.save(value)
        do { try await store.importData(Data(repeating: 0, count: ConversationBackup.maximumBytes + 1)); XCTFail("Oversized import accepted") } catch { }
        let saved = try await store.load(id: value.id)
        XCTAssertEqual(saved?.title, "Keep")
    }
    func testDeleteAllRemovesConversationsAndMemory() async throws {
        let store = try SQLiteConversationStore(url: temporaryDatabase())
        try await store.save(Conversation(title: "Private"))
        try await store.saveMemory(MemoryNote(content: "Prefers concise replies"))
        try await store.deleteAll()
        let conversations = try await store.list(includeArchived: true)
        let memories = try await store.memories()
        XCTAssertTrue(conversations.isEmpty)
        XCTAssertTrue(memories.isEmpty)
    }
    func testImportRejectsAttachmentTraversalBeforeWriting() async throws {
        let store = try SQLiteConversationStore(url: temporaryDatabase())
        let attachment = ChatAttachment(name: "Secret", relativePath: "../../secret", mediaType: "text/plain", byteCount: 2)
        let value = Conversation(messages: [ChatMessage(role: .user, content: "File", attachments: [attachment])])
        let export = ConversationBackup(conversations: [value], memories: [])
        let data = try JSONEncoder().encode(export)
        do { try await store.importData(data); XCTFail("Path traversal accepted") } catch { }
        let values = try await store.list()
        XCTAssertTrue(values.isEmpty)
    }
    private func temporaryDatabase() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite") }
}
