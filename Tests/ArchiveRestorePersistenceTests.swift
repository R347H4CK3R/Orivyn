import XCTest
import SQLite3
@testable import JarvisEVO

final class ArchiveRestorePersistenceTests: XCTestCase {
    let sha = String(repeating: "a", count: 64)
    func testAdditiveCommitReceiptAndReplayPreserveLocalEdits() async throws {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteConversationStore(url: url)
        let epoch = try await store.textReceiveEpoch()
        let job = UUID(); let incoming = Conversation(title: "Imported", messages: [ChatMessage(role: .user, content: "Text")])
        let receipt = try await store.applyArchiveRestore(jobID: job, archiveSHA256: sha, expectedEpoch: epoch, conversations: [incoming])
        XCTAssertEqual(receipt.writtenConversations, 1)
        var edited = incoming; edited.title = "Local edit"; try await store.save(edited)
        let replay = try await store.applyArchiveRestore(jobID: job, archiveSHA256: sha, expectedEpoch: epoch, conversations: [incoming])
        XCTAssertEqual(replay, receipt)
        let actual = try await store.load(id: incoming.id); XCTAssertEqual(actual?.title, "Local edit")
        let reopened = try SQLiteConversationStore(url: url)
        let recovered = try await reopened.archiveRestoreReceipt(jobID: job); XCTAssertEqual(recovered, receipt)
    }
    func testSecondWriteFailureRollsBackConversationsAndReceipt() async throws {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteConversationStore(url: url); let epoch = try await store.textReceiveEpoch(); let job = UUID()
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TRIGGER reject_archive BEFORE INSERT ON conversations WHEN NEW.title='Reject' BEGIN SELECT RAISE(ABORT,'injected'); END", nil, nil, nil), SQLITE_OK)
        do { _ = try await store.applyArchiveRestore(jobID: job, archiveSHA256: sha, expectedEpoch: epoch, conversations: [Conversation(title: "First"), Conversation(title: "Reject")]); XCTFail("Expected rollback") } catch { }
        let rows = try await store.list(includeArchived: true); XCTAssertTrue(rows.isEmpty)
        let receipt = try await store.archiveRestoreReceipt(jobID: job); XCTAssertNil(receipt)
    }
    func testDeletionClearsReceiptAndInvalidatesPendingEpoch() async throws {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteConversationStore(url: url); let epoch = try await store.textReceiveEpoch(); let job = UUID()
        let incoming = Conversation(title: "Erase")
        _ = try await store.applyArchiveRestore(jobID: job, archiveSHA256: sha, expectedEpoch: epoch, conversations: [incoming])
        _ = try await store.deleteAll()
        let receipt = try await store.archiveRestoreReceipt(jobID: job); XCTAssertNil(receipt)
        do { _ = try await store.applyArchiveRestore(jobID: job, archiveSHA256: sha, expectedEpoch: epoch, conversations: [incoming]); XCTFail("Stale restore cannot resurrect history") } catch { }
        let rows = try await store.list(includeArchived: true); XCTAssertTrue(rows.isEmpty)
    }

    func testIdentityCannotBeReboundToDifferentPayloadOrArchive() async throws {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteConversationStore(url: url); let epoch = try await store.textReceiveEpoch(); let job = UUID()
        let incoming = Conversation(title: "Original")
        let receipt = try await store.applyArchiveRestore(jobID: job, archiveSHA256: sha, expectedEpoch: epoch, conversations: [incoming])
        var changed = incoming; changed.title = "Changed plan"
        do { _ = try await store.applyArchiveRestore(jobID: job, archiveSHA256: sha, expectedEpoch: epoch, conversations: [changed]); XCTFail("Plan mismatch") } catch { }
        do { _ = try await store.applyArchiveRestore(jobID: job, archiveSHA256: String(repeating: "b", count: 64), expectedEpoch: epoch, conversations: [incoming]); XCTFail("Archive mismatch") } catch { }
        let replay = try await store.applyArchiveRestore(jobID: UUID(), archiveSHA256: sha, expectedEpoch: epoch, conversations: [incoming])
        XCTAssertEqual(replay, receipt)
        let rows = try await store.list(includeArchived: true); XCTAssertEqual(rows.count, 1)
    }
    func testExistingLocalConversationIsPreservedInFirstImport() async throws {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteConversationStore(url: url); let epoch = try await store.textReceiveEpoch()
        let local = Conversation(title: "Local"); try await store.save(local)
        var incoming = local; incoming.title = "Archive"
        let receipt = try await store.applyArchiveRestore(jobID: UUID(), archiveSHA256: sha, expectedEpoch: epoch, conversations: [incoming, Conversation(title: "New")])
        XCTAssertEqual(receipt.writtenConversations, 1); XCTAssertEqual(receipt.preservedConversations, 1)
        let retained = try await store.load(id: local.id); XCTAssertEqual(retained, local)
    }
    func testReceiptWriteFailureRollsBackConversationWrites() async throws {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteConversationStore(url: url); let epoch = try await store.textReceiveEpoch(); let job = UUID()
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TRIGGER reject_receipt BEFORE INSERT ON archive_restore_receipts BEGIN SELECT RAISE(ABORT,'injected'); END", nil, nil, nil), SQLITE_OK)
        do { _ = try await store.applyArchiveRestore(jobID: job, archiveSHA256: sha, expectedEpoch: epoch, conversations: [Conversation(title: "Not committed")]); XCTFail("Receipt failure") } catch { }
        let rows = try await store.list(includeArchived: true); XCTAssertTrue(rows.isEmpty)
        let receipt = try await store.archiveRestoreReceipt(jobID: job); XCTAssertNil(receipt)
    }
    func testCancelledTaskCannotCommitAndUnverifiedAttachmentsAreRejected() async throws {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteConversationStore(url: url); let epoch = try await store.textReceiveEpoch(); let job = UUID()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.applyArchiveRestore(jobID: job, archiveSHA256: String(repeating: "a", count: 64), expectedEpoch: epoch, conversations: [Conversation(title: "Cancelled")])
        }
        do { _ = try await task.value; XCTFail("Cancelled task") } catch is CancellationError { } catch { XCTFail("Wrong cancellation error") }
        let attachment = ChatAttachment(name: "Unknown.txt", relativePath: "unknown.txt", mediaType: "text/plain", byteCount: 1)
        let incoming = Conversation(messages: [ChatMessage(role: .user, content: "Text", attachments: [attachment])])
        do { _ = try await store.applyArchiveRestore(jobID: job, archiveSHA256: sha, expectedEpoch: epoch, conversations: [incoming]); XCTFail("Missing attachment ownership proof") } catch { }
        let rows = try await store.list(includeArchived: true); XCTAssertTrue(rows.isEmpty)
    }

    func testCorruptedReceiptIdentityFailsClosedOnReplay() async throws {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteConversationStore(url: url); let epoch = try await store.textReceiveEpoch(); let job = UUID()
        let incoming = Conversation(title: "Original")
        _ = try await store.applyArchiveRestore(jobID: job, archiveSHA256: sha, expectedEpoch: epoch, conversations: [incoming])
        let corrupt = ArchiveRestoreReceipt(jobID: UUID(), archiveSHA256: sha, epoch: epoch, writtenConversations: 1, preservedConversations: 0)
        let hex = try JSONEncoder().encode(corrupt).map { String(format: "%02x", $0) }.joined()
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "UPDATE archive_restore_receipts SET receipt=X'" + hex + "'", nil, nil, nil), SQLITE_OK)
        do { _ = try await store.applyArchiveRestore(jobID: job, archiveSHA256: sha, expectedEpoch: epoch, conversations: [incoming]); XCTFail("Corrupt receipt identity") } catch { }
    }
    func testArchiveLookupRecoversCanonicalReceiptAndRejectsMalformedHash() async throws {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteConversationStore(url: url); let epoch = try await store.textReceiveEpoch()
        let missing = try await store.archiveRestoreReceipt(archiveSHA256: sha); XCTAssertNil(missing)
        let receipt = try await store.applyArchiveRestore(jobID: UUID(), archiveSHA256: sha, expectedEpoch: epoch, conversations: [Conversation(title: "Original")])
        let reopened = try SQLiteConversationStore(url: url)
        let recovered = try await reopened.archiveRestoreReceipt(archiveSHA256: sha); XCTAssertEqual(recovered, receipt)
        for invalid in ["", String(repeating: "a", count: 63), String(repeating: "a", count: 65), String(repeating: "A", count: 64), String(repeating: "g", count: 64)] {
            do { _ = try await reopened.archiveRestoreReceipt(archiveSHA256: invalid); XCTFail("Invalid digest accepted") } catch { }
        }
        let corrupt = ArchiveRestoreReceipt(jobID: UUID(), archiveSHA256: sha, epoch: epoch, writtenConversations: 1, preservedConversations: 0)
        let hex = try JSONEncoder().encode(corrupt).map { String(format: "%02x", $0) }.joined()
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "UPDATE archive_restore_receipts SET receipt=X'" + hex + "'", nil, nil, nil), SQLITE_OK)
        do { _ = try await reopened.archiveRestoreReceipt(archiveSHA256: sha); XCTFail("Corrupt receipt accepted") } catch { }
    }

}
