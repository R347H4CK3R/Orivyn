import XCTest
@testable import JarvisEVO

/// Synthetic metadata only. Real SQLite transactions, not image decoding/provenance.
final class ImageIdentityPersistenceTests: XCTestCase {
    private func image(_ id: UUID, bytes: Int) -> ChatAttachment {
        ChatAttachment(id: id, name: "Fixture", relativePath: id.uuidString + ".png",
                       mediaType: "image/png", byteCount: bytes, previewRelativePath: id.uuidString + "-preview.jpg")
    }
    private func conversation(_ image: ChatAttachment) -> Conversation {
        Conversation(messages: [ChatMessage(role: .user, content: "Fixture", attachments: [image])])
    }
    private func location() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("history.sqlite")
    }
    func testConflictingSharedBranchSavePreservesBothExistingRows() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try SQLiteConversationStore(url: url)
        let id = UUID(), first = conversation(image(UUID(), bytes: 100))
        let shared = image(id, bytes: 100)
        let a = conversation(shared), b = conversation(shared)
        try await store.save(first); try await store.save(a); try await store.save(b)
        var changed = a
        changed.messages[0].attachments = [image(id, bytes: 101)]
        do { try await store.save(changed); XCTFail("Conflicting image identity accepted") }
        catch { XCTAssertEqual(error as? ConversationError, .unsafeAttachment) }
        let actualA = try await store.load(id: a.id), actualB = try await store.load(id: b.id)
        XCTAssertEqual(actualA, a); XCTAssertEqual(actualB, b)
        let rows = try await store.list()
        XCTAssertEqual(rows.count, 3)
    }
    func testConcurrentWritersCannotCommitConflictingImageIdentities() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = try SQLiteConversationStore(url: url), second = try SQLiteConversationStore(url: url)
        let id = UUID(), a = conversation(image(UUID(), bytes: 100))
        try await first.save(a)
        let left = conversation(image(id, bytes: 100)), right = conversation(image(id, bytes: 101))
        let results = await withTaskGroup(of: String.self, returning: [String].self) { group in
            group.addTask { do { try await first.save(left); return "saved" } catch ConversationError.unsafeAttachment { return "unsafe" } catch { return "unexpected: \(error)" } }
            group.addTask { do { try await second.save(right); return "saved" } catch ConversationError.unsafeAttachment { return "unsafe" } catch { return "unexpected: \(error)" } }
            var outcomes: [String] = []
            for await result in group { outcomes.append(result) }
            return outcomes
        }
        XCTAssertEqual(results.sorted(), ["saved", "unsafe"])
        let reopened = try SQLiteConversationStore(url: url)
        let rows = try await reopened.list()
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.filter { $0.id == left.id || $0.id == right.id }.count, 1)
        XCTAssertTrue(rows.contains(a))
        XCTAssertTrue(rows.contains(left) || rows.contains(right))
    }
    func testPartialConflictRejectsBeforeWritesButCompleteReplacementIsAccepted() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try SQLiteConversationStore(url: url)
        let shared = image(UUID(), bytes: 100)
        var a = conversation(shared), b = conversation(shared)
        try await store.save(a); try await store.save(b)
        let originalA = a, originalB = b
        let updated = image(shared.id, bytes: 101)
        // Same ID must stay consistent with every retained reference.
        var conflicting = shared; conflicting.byteCount = 101
        a.messages[0].attachments = [conflicting]
        let note = MemoryNote(content: "Only committed with a valid complete snapshot")
        let partial = try JSONEncoder().encode(ConversationBackup(conversations: [a], memories: [note]))
        do { _ = try await store.importData(partial); XCTFail("Partial conflict accepted") }
        catch { XCTAssertEqual(error as? ConversationError, .unsafeAttachment) }
        let retainedA = try await store.load(id: a.id), retainedB = try await store.load(id: b.id)
        let notes = try await store.memories()
        XCTAssertEqual(retainedA, originalA); XCTAssertEqual(retainedB, originalB); XCTAssertTrue(notes.isEmpty)
        a.messages[0].attachments = [updated]; b.messages[0].attachments = [updated]
        let complete = try JSONEncoder().encode(ConversationBackup(conversations: [a,b], memories: [note]))
        let summary = try await store.importData(complete)
        XCTAssertEqual(summary.writtenConversations, 2); XCTAssertEqual(summary.writtenMemories, 1)
        let reopened = try SQLiteConversationStore(url: url)
        let newA = try await reopened.load(id: a.id), newB = try await reopened.load(id: b.id)
        XCTAssertEqual(newA, a); XCTAssertEqual(newB, b)
        let committedNotes = try await reopened.memories()
        XCTAssertEqual(committedNotes, [note])
    }
}
