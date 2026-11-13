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
    func testImportedMemoryCreationDateControlsOrderingAfterReplacement() async throws {
        let store = try SQLiteConversationStore(url: temporaryDatabase())
        let id = UUID()
        try await store.saveMemory(MemoryNote(id: id, content: "Old", createdAt: Date(timeIntervalSince1970: 10)))
        try await store.saveMemory(MemoryNote(content: "Middle", createdAt: Date(timeIntervalSince1970: 20)))
        let replacement = MemoryNote(id: id, content: "Imported", createdAt: Date(timeIntervalSince1970: 30))
        try await store.importData(JSONEncoder().encode(ConversationBackup(conversations: [], memories: [replacement])))
        let notes = try await store.memories()
        XCTAssertEqual(notes.first, replacement)
        XCTAssertEqual(notes.count, 2)
    }

    func testSearchRetainsTextAfterEmbeddedNul() async throws {
        let store = try SQLiteConversationStore(url: temporaryDatabase())
        let conversation = Conversation(title: "Nul", messages: [ChatMessage(role: .user, content: "before\0afterunique")])
        try await store.save(conversation)
        let conversations = try await store.list(query: "afterunique")
        XCTAssertEqual(conversations.map(\.id), [conversation.id])
        let note = MemoryNote(content: "before\0memoryunique")
        try await store.saveMemory(note)
        let notes = try await store.memories(query: "memoryunique")
        XCTAssertEqual(notes, [note])
    }

    func testPreserveLocalImportAddsMissingWithoutOverwritingConflicts() async throws {
        let store = try SQLiteConversationStore(url: temporaryDatabase())
        let local = Conversation(title: "Local", messages: [ChatMessage(role: .user, content: "Keep newer turn")])
        let note = MemoryNote(content: "Keep local memory")
        try await store.save(local)
        try await store.saveMemory(note)
        var incoming = local
        incoming.messages = []
        incoming.title = "Old backup"
        var changedNote = note
        changedNote.content = "Other device"
        let newConversation = Conversation(title: "Other chat")
        let backup = ConversationBackup(conversations: [incoming, newConversation], memories: [changedNote])
        let data = try JSONEncoder().encode(backup)
        let summary = try await store.importData(data, policy: .preserveLocal)
        XCTAssertEqual(summary.writtenConversations, 1)
        XCTAssertEqual(summary.skippedConversations, 1)
        XCTAssertEqual(summary.skippedMemories, 1)
        let retained = try await store.load(id: local.id)
        let memories = try await store.memories()
        XCTAssertEqual(retained, local)
        XCTAssertEqual(memories, [note])
        let repeated = try await store.importData(data, policy: .preserveLocal)
        XCTAssertEqual(repeated.writtenConversations, 0)
        let all = try await store.list(includeArchived: true)
        XCTAssertEqual(all.count, 2)
    }

    private func temporaryDatabase() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite") }
}
