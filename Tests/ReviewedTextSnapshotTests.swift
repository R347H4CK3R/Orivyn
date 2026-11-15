import XCTest
import SQLite3
@testable import JarvisEVO

final class ReviewedTextSnapshotTests: XCTestCase {
    private func store() throws -> SQLiteConversationStore {
        try SQLiteConversationStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite"))
    }
    private func chat(_ title: String = "Chosen") -> Conversation {
        Conversation(title: title, messages: [ChatMessage(role: .user, content: "Exact reviewed text")])
    }
    func testExportsOnlySelectedTextAndNoMemories() async throws {
        let db = try store(), chosen = chat(), excluded = chat("Excluded")
        try await db.save(chosen); try await db.save(excluded)
        try await db.saveMemory(MemoryNote(content: "Do not export this memory"))
        let snapshot = try await db.exportTextSnapshot(ids: [chosen.id])
        let backup = try JSONDecoder().decode(ConversationBackup.self, from: snapshot.data)
        XCTAssertEqual(backup.conversations, [chosen]); XCTAssertTrue(backup.memories.isEmpty)
        XCTAssertEqual(snapshot.conversations, backup.conversations)
        XCTAssertEqual(snapshot.messageCount, 1)
    }
    func testSnapshotBytesStayFixedAfterEditAndDeletion() async throws {
        let db = try store(); var chosen = chat()
        try await db.save(chosen)
        let snapshot = try await db.exportTextSnapshot(ids: [chosen.id]), bytes = snapshot.data
        chosen.messages[0].content = "Later edit"; try await db.save(chosen)
        try await db.delete(id: chosen.id)
        XCTAssertEqual(snapshot.data, bytes)
        XCTAssertEqual(snapshot.conversations[0].messages[0].content, "Exact reviewed text")
        let receiving = try store()
        _ = try await receiving.importData(snapshot.data, policy: .keepBoth)
        let imported = try await receiving.list()
        XCTAssertEqual(imported, snapshot.conversations)
    }
    func testEmptyMissingAndOversizedSelectionFailWithoutPartialExport() async throws {
        let db = try store(), chosen = chat(); try await db.save(chosen)
        for ids: Set<UUID> in [[], [chosen.id, UUID()], Set((0..<101).map { _ in UUID() })] {
            do { _ = try await db.exportTextSnapshot(ids: ids); XCTFail("Invalid selection exported") } catch { }
        }
        let remaining = try await db.list(); XCTAssertEqual(remaining, [chosen])
    }
    func testAttachmentsAreRejectedInsteadOfSilentlyDropped() async throws {
        let db = try store(); var chosen = chat()
        chosen.messages[0].attachments = [ChatAttachment(name: "private.txt", relativePath: "private.txt", mediaType: "text/plain", byteCount: 12, extractedText: "Private attachment text")]
        try await db.save(chosen)
        do { _ = try await db.exportTextSnapshot(ids: [chosen.id]); XCTFail("Attachment accepted") } catch { }
    }
    func testAllUnfinishedMessageStatesAreRejected() async throws {
        let db = try store()
        for state in [MessageState.streaming, .failed, .interrupted] {
            var chosen = chat(); chosen.messages[0].state = state; try await db.save(chosen)
            do { _ = try await db.exportTextSnapshot(ids: [chosen.id]); XCTFail("Unfinished text accepted") } catch { }
        }
    }
    func testReviewMessageAndByteLimitsReject() async throws {
        let db = try store()
        let many = Conversation(messages: (0..<1001).map { _ in ChatMessage(role: .user, content: "x") })
        try await db.save(many)
        do { _ = try await db.exportTextSnapshot(ids: [many.id]); XCTFail("Review bound exceeded") } catch { }
        let large = Conversation(messages: (0..<6).map { _ in ChatMessage(role: .user, content: String(repeating: "x", count: 900_000)) })
        try await db.save(large)
        do { _ = try await db.exportTextSnapshot(ids: [large.id]); XCTFail("Byte bound exceeded") } catch { }
    }
    func testCanceledReadDoesNotLeakTransactionAndNextReadSucceeds() async throws {
        let db = try store(), chosen = chat(); try await db.save(chosen)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await db.exportTextSnapshot(ids: [chosen.id]) }
        do { _ = try await task.value; XCTFail("Canceled export succeeded") } catch is CancellationError { }
        let snapshot = try await db.exportTextSnapshot(ids: [chosen.id]); XCTAssertEqual(snapshot.conversations, [chosen])
    }
    func testArchivedSelectedConversationIsIncluded() async throws {
        let db = try store(); var chosen = chat(); chosen.isArchived = true; try await db.save(chosen)
        let snapshot = try await db.exportTextSnapshot(ids: [chosen.id]); XCTAssertEqual(snapshot.conversations, [chosen])
    }
}
