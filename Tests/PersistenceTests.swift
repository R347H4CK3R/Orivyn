import XCTest
import SQLite3
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

    @MainActor
    func testCancelledImportDoesNotWriteOrReplaceLocalRecords() async throws {
        let store = try SQLiteConversationStore(url: temporaryDatabase())
        let original = Conversation(title: "Keep local")
        try await store.save(original)
        var replacement = original
        replacement.title = "Must not commit"
        let data = try JSONEncoder().encode(ConversationBackup(conversations: [replacement], memories: []))
        let task = Task { try await store.importData(data) }
        task.cancel() // The inherited MainActor task cannot start before this cancellation.
        do { _ = try await task.value; XCTFail("Cancelled import committed") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let retained = try await store.load(id: original.id)
        XCTAssertEqual(retained, original)
    }

    func testFailedMemoryWriteRollsBackEarlierConversationChangesAndAllowsRetry() async throws {
        let url = temporaryDatabase()
        let store = try SQLiteConversationStore(url: url)
        let original = Conversation(title: "Keep original")
        try await store.save(original)
        var replacement = original
        replacement.title = "Replacement"
        let addition = Conversation(title: "New imported row")
        let note = MemoryNote(content: "Import memory")
        let data = try JSONEncoder().encode(ConversationBackup(conversations: [replacement, addition], memories: [note]))
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "CREATE TRIGGER reject_memory BEFORE INSERT ON memory BEGIN SELECT RAISE(ABORT, 'test failure'); END;", nil, nil, nil), SQLITE_OK)
        do { _ = try await store.importData(data); XCTFail("Failed memory write must reject the entire import") }
        catch { XCTAssertTrue(error is DatabaseError) }
        let retained = try await store.load(id: original.id)
        let absent = try await store.load(id: addition.id)
        let memories = try await store.memories()
        XCTAssertEqual(retained, original)
        XCTAssertNil(absent)
        XCTAssertTrue(memories.isEmpty)
        XCTAssertEqual(sqlite3_exec(connection, "DROP TRIGGER reject_memory", nil, nil, nil), SQLITE_OK)
        let summary = try await store.importData(data)
        XCTAssertEqual(summary.writtenConversations, 2)
        XCTAssertEqual(summary.writtenMemories, 1)
        let retried = try await store.load(id: original.id)
        XCTAssertEqual(retried, replacement)
    }

    func testExportUsesOneSnapshotAcrossConversationAndMemoryTables() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("snapshot.sqlite")
        let reader = try SQLiteConversationStore(url: url), writer = try SQLiteConversationStore(url: url)
        let conversationID = UUID(), memoryID = UUID()
        let filler = (0..<400).map { _ in Conversation(messages: [ChatMessage(role: .user, content: String(repeating: "x", count: 2000))]) }
        func snapshot(_ generation: Int, initial: Bool = false) throws -> Data {
            try JSONEncoder().encode(ConversationBackup(
                conversations: (initial ? filler : []) + [Conversation(id: conversationID, title: String(generation))],
                memories: [MemoryNote(id: memoryID, content: String(generation))]))
        }
        try await writer.importData(snapshot(0, initial: true))
        let inputs = try (1...120).map { try snapshot($0) }
        let writes = Task.detached { for data in inputs { try await writer.importData(data) } }
        var mismatch: String?
        do {
            for _ in 0..<120 {
                let backup = try JSONDecoder().decode(ConversationBackup.self, from: await reader.exportData())
                let conversation = try XCTUnwrap(backup.conversations.first { $0.id == conversationID })
                let memory = try XCTUnwrap(backup.memories.first { $0.id == memoryID })
                if conversation.title != memory.content {
                    mismatch = "conversation generation \(conversation.title), memory generation \(memory.content)"
                    break
                }
            }
        } catch {
            _ = await writes.result
            throw error
        }
        try await writes.value
        XCTAssertNil(mismatch, "Export combined independently committed snapshots: \(mismatch ?? "")")
        // A completed export must also release its read transaction for subsequent writes.
        try await reader.save(Conversation(title: "Reader can write after export"))
    }

    func testFailedExportReleasesReadTransactionForRepairAndLaterWrites() async throws {
        let url = temporaryDatabase()
        let store = try SQLiteConversationStore(url: url)
        let original = Conversation(title: "Recoverable")
        try await store.save(original)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "UPDATE conversations SET payload = X'7B'", nil, nil, nil), SQLITE_OK)
        do { _ = try await store.exportData(); XCTFail("Corrupt row must not be exported") }
        catch { XCTAssertTrue(error is DecodingError) }
        // Repair the fixture through the same store: BEGIN must no longer be held.
        try await store.save(original)
        let restored = try JSONDecoder().decode(ConversationBackup.self, from: await store.exportData())
        XCTAssertEqual(restored.conversations, [original])
        try await store.save(Conversation(title: "After recovered export"))
        let rows = try await store.list()
        XCTAssertEqual(rows.count, 2)
    }

    func testDuplicateDocumentAndMixedAttachmentIDsRejectBeforeChangingBackupState() async throws {
        let store = try SQLiteConversationStore(url: temporaryDatabase())
        let original = Conversation(title: "Keep original")
        try await store.save(original)
        let id = UUID()
        let document = ChatAttachment(id: id, name: "First", relativePath: "first.txt", mediaType: "text/plain", byteCount: 10, extractedText: "First document")
        let second = ChatAttachment(id: id, name: "Second", relativePath: "second.txt", mediaType: "text/plain", byteCount: 20, extractedText: "Different document")
        let image = ChatAttachment(id: id, name: "Image", relativePath: id.uuidString + ".png", mediaType: "image/png", byteCount: 30)
        for duplicate in [second, image] {
            let malformed = Conversation(messages: [ChatMessage(role: .user, content: "Ambiguous IDs", attachments: [document, duplicate])])
            do { try await store.save(malformed); XCTFail("Duplicate per-message attachment IDs accepted by save") }
            catch { XCTAssertEqual(error as? ConversationError, .unsafeAttachment) }
            var replacement = original; replacement.title = "Must not replace"
            let data = try JSONEncoder().encode(ConversationBackup(conversations: [replacement, malformed], memories: [MemoryNote(content: "Must not import")]))
            do { _ = try await store.importData(data); XCTFail("Duplicate attachment IDs accepted by import") }
            catch { XCTAssertEqual(error as? ConversationError, .unsafeAttachment) }
            let rows = try await store.list(), notes = try await store.memories()
            XCTAssertEqual(rows, [original]); XCTAssertTrue(notes.isEmpty)
        }
    }
    func testAttachmentIdentityCanBeSharedAcrossMessagesButDistinctWithinEachMessage() async throws {
        let store = try SQLiteConversationStore(url: temporaryDatabase())
        let first = ChatAttachment(name: "Shared", relativePath: "shared.txt", mediaType: "text/plain", byteCount: 10)
        let second = ChatAttachment(name: "Other", relativePath: "other.txt", mediaType: "text/plain", byteCount: 20)
        let conversation = Conversation(messages: [
            ChatMessage(role: .user, content: "First turn", attachments: [first, second]),
            ChatMessage(role: .user, content: "Second turn", attachments: [first])])
        try await store.save(conversation)
        let restored = try await store.load(id: conversation.id)
        XCTAssertEqual(restored, conversation)
    }

    func testBackupRecordCountBoundaryRoundTripsBothCollectionsAtTenThousand() async throws {
        let first = try SQLiteConversationStore(url: temporaryDatabase())
        let second = try SQLiteConversationStore(url: temporaryDatabase())
        let conversations = (0..<10_000).map { Conversation(title: "Boundary conversation \($0)") }
        let notes = (0..<10_000).map { MemoryNote(content: "Boundary memory \($0)") }
        try await first.importData(JSONEncoder().encode(ConversationBackup(conversations: conversations, memories: notes)))
        let exported = try await first.exportData()
        let decoded = try JSONDecoder().decode(ConversationBackup.self, from: exported)
        XCTAssertEqual(decoded.conversations.count, 10_000)
        XCTAssertEqual(decoded.memories.count, 10_000)
        try await second.importData(exported)
        let restoredConversations = try await second.list(includeArchived: true)
        let restoredNotes = try await second.memories()
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: restoredConversations.map { ($0.id, $0) }),
                       Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) }))
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: restoredNotes.map { ($0.id, $0) }),
                       Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) }))
    }

    func testExportRejectsTenThousandAndOneRecordsWithoutTruncationAndReleasesTransaction() async throws {
        for memoryOverflow in [true, false] {
            let store = try SQLiteConversationStore(url: temporaryDatabase())
            let sentinel = Conversation(title: "Preserve sentinel")
            let conversations = memoryOverflow ? [sentinel] : (0..<10_000).map { Conversation(title: "Conversation \($0)") }
            let notes = memoryOverflow ? (0..<10_000).map { MemoryNote(content: "Memory \($0)") } : []
            try await store.importData(JSONEncoder().encode(ConversationBackup(conversations: conversations, memories: notes)))
            // Ordinary saves remain allowed. Only a non-restorable export must be rejected.
            if memoryOverflow { try await store.saveMemory(MemoryNote(content: "Record 10001")) }
            else { try await store.save(Conversation(title: "Record 10001")) }
            let beforeConversations = try await store.list(includeArchived: true)
            let beforeNotes = try await store.memories()
            XCTAssertEqual(memoryOverflow ? beforeNotes.count : beforeConversations.count, 10_001)
            do { _ = try await store.exportData(); XCTFail("Non-restorable over-count export accepted") }
            catch {
                XCTAssertTrue(error is ConversationError)
                XCTAssertTrue(error.localizedDescription.contains("10000"), "Count-limit error must identify the supported bound")
            }
            let afterConversations = try await store.list(includeArchived: true)
            let afterNotes = try await store.memories()
            XCTAssertEqual(afterConversations, beforeConversations)
            XCTAssertEqual(afterNotes, beforeNotes)
            // save starts BEGIN IMMEDIATE on the same connection: success proves failed
            // export rolled back its read transaction rather than leaving it held.
            var changed = beforeConversations[0]; changed.title = "Write after rejected export"
            try await store.save(changed)
            let written = try await store.load(id: changed.id)
            XCTAssertEqual(written, changed)
        }
    }

    private func temporaryDatabase() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite") }
}
