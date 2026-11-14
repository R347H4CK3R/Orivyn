import XCTest
import SQLite3
@testable import JarvisEVO

final class TextReceivePersistenceTests: XCTestCase {
    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite") }
    private func payload(_ values: [Conversation], memories: [MemoryNote] = []) throws -> Data {
        try JSONEncoder().encode(ConversationBackup(conversations: values, memories: memories))
    }
    private func identity(_ store: SQLiteConversationStore, transfer: UUID = UUID(), peer: UInt8 = 1, generation: UUID = UUID()) async throws -> ReviewedTextReceiveIdentity {
        ReviewedTextReceiveIdentity(epoch: try await store.textReceiveEpoch(), transfer: transfer, peerCertificateSHA256: Data(repeating: peer, count: 32), pairingGeneration: generation)
    }
    private func sql(_ url: URL, _ query: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, query, nil, nil, nil), SQLITE_OK)
    }
    func testConflictRetryAfterReopenDoesNotDuplicateOrOverwriteLocalEdit() async throws {
        let path = url(), local = Conversation(title: "Local")
        let store = try SQLiteConversationStore(url: path)
        try await store.save(local)
        var remote = local; remote.title = "Remote"
        let bytes = try payload([remote]), scope = try await identity(store)
        let first = try await store.receiveReviewedText(bytes, identity: scope)
        XCTAssertEqual(first.copiedConversations, 1)
        var edited = local; edited.title = "New local edit"
        try await store.save(edited)
        let reopened = try SQLiteConversationStore(url: path)
        let retried = try await reopened.receiveReviewedText(bytes, identity: scope)
        XCTAssertEqual(retried.copiedConversations, 1)
        let all = try await reopened.list()
        XCTAssertEqual(Set(all.map(\.title)), ["New local edit", "Remote"])
        XCTAssertEqual(all.count, 2)
    }
    func testChangedPayloadPeerAndGenerationRejectSameTransfer() async throws {
        let store = try SQLiteConversationStore(url: url())
        let bytes = try payload([Conversation(title: "Accepted")]), scope = try await identity(store)
        _ = try await store.receiveReviewedText(bytes, identity: scope)
        let peer = ReviewedTextReceiveIdentity(epoch: scope.epoch, transfer: scope.transfer, peerCertificateSHA256: Data(repeating: 2, count: 32), pairingGeneration: scope.pairingGeneration)
        let generation = ReviewedTextReceiveIdentity(epoch: scope.epoch, transfer: scope.transfer, peerCertificateSHA256: scope.peerCertificateSHA256, pairingGeneration: UUID())
        for changed in [peer, generation] {
            do { _ = try await store.receiveReviewedText(bytes, identity: changed); XCTFail("Scope substitution accepted") } catch { }
        }
        do { _ = try await store.receiveReviewedText(try payload([Conversation(title: "Changed")]), identity: scope); XCTFail("Payload substitution accepted") } catch { }
        let all = try await store.list(); XCTAssertEqual(all.map(\.title), ["Accepted"])
    }
    func testReceiptFailureRollsBackContentAndRetryWorks() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path)
        let bytes = try payload([Conversation(title: "Atomic")]), scope = try await identity(store)
        try sql(path, "CREATE TRIGGER reject_receipt BEFORE INSERT ON text_receive_receipts BEGIN SELECT RAISE(ABORT, 'fixture'); END;")
        do { _ = try await store.receiveReviewedText(bytes, identity: scope); XCTFail("Receipt failure accepted") } catch { }
        let empty = try await store.list(); XCTAssertTrue(empty.isEmpty)
        try sql(path, "DROP TRIGGER reject_receipt")
        let result = try await store.receiveReviewedText(bytes, identity: scope)
        XCTAssertEqual(result.writtenConversations, 1)
    }
    func testContentFailureDoesNotCommitReceipt() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path)
        let bytes = try payload([Conversation(title: "Atomic")]), scope = try await identity(store)
        try sql(path, "CREATE TRIGGER reject_content BEFORE INSERT ON conversations BEGIN SELECT RAISE(ABORT, 'fixture'); END;")
        do { _ = try await store.receiveReviewedText(bytes, identity: scope); XCTFail("Content failure accepted") } catch { }
        try sql(path, "DROP TRIGGER reject_content")
        _ = try await store.receiveReviewedText(bytes, identity: scope)
        let all = try await store.list(); XCTAssertEqual(all.count, 1)
    }
    func testDeleteAllRotatesEpochAndRejectsOldRetry() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path)
        let bytes = try payload([Conversation(title: "Erase")]), scope = try await identity(store)
        _ = try await store.receiveReviewedText(bytes, identity: scope)
        try await store.deleteAll()
        let reopened = try SQLiteConversationStore(url: path)
        let epoch = try await reopened.textReceiveEpoch(); XCTAssertNotEqual(epoch, scope.epoch)
        do { _ = try await reopened.receiveReviewedText(bytes, identity: scope); XCTFail("Stale receive restored erased data") } catch { }
        let all = try await reopened.list(); XCTAssertTrue(all.isEmpty)
    }
    func testIndividualDeleteClearsReceiptTextAndInvalidatesOldReceive() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path)
        let value = Conversation(title: "Erase this text")
        let bytes = try payload([value]), scope = try await identity(store)
        _ = try await store.receiveReviewedText(bytes, identity: scope)
        try await store.delete(id: value.id)
        do { _ = try await store.receiveReviewedText(bytes, identity: scope); XCTFail("Deleted text restored") } catch { }
        let all = try await store.list(); XCTAssertTrue(all.isEmpty)
        var db: OpaquePointer?; sqlite3_open(path.path, &db)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM text_receive_receipts", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 0)
    }
    func testFailedErasePreservesEpochAndReceipt() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path)
        let bytes = try payload([Conversation(title: "Keep")]), scope = try await identity(store)
        _ = try await store.receiveReviewedText(bytes, identity: scope)
        try sql(path, "CREATE TRIGGER reject_epoch BEFORE UPDATE ON text_receive_epoch BEGIN SELECT RAISE(ABORT, 'fixture'); END;")
        do { try await store.deleteAll(); XCTFail("Erase failure accepted") } catch { }
        let epoch = try await store.textReceiveEpoch(); XCTAssertEqual(epoch, scope.epoch)
        _ = try await store.receiveReviewedText(bytes, identity: scope)
        let all = try await store.list(); XCTAssertEqual(all.count, 1)
    }
    func testAttachmentsMemoriesAndStreamingRejectWholeBatch() async throws {
        let store = try SQLiteConversationStore(url: url()), scope = try await identity(store)
        let attachment = ChatAttachment(name: "File", relativePath: "file.txt", mediaType: "text/plain", byteCount: 1)
        let attached = Conversation(messages: [ChatMessage(role: .user, content: "File", attachments: [attachment])])
        let streaming = Conversation(messages: [ChatMessage(role: .assistant, content: "Partial", state: .streaming)])
        for bytes in [try payload([attached]), try payload([streaming]), try payload([], memories: [MemoryNote(content: "Private")])] {
            do { _ = try await store.receiveReviewedText(bytes, identity: scope); XCTFail("Unsupported scope accepted") } catch { }
        }
        let all = try await store.list(); XCTAssertTrue(all.isEmpty)
    }
    func testConcurrentConnectionsCommitOnlyOneConflictCopy() async throws {
        let path = url(), local = Conversation(title: "Local")
        let first = try SQLiteConversationStore(url: path), second = try SQLiteConversationStore(url: path)
        try await first.save(local)
        var remote = local; remote.title = "Remote"
        let bytes = try payload([remote]), scope = try await identity(first)
        async let a = first.receiveReviewedText(bytes, identity: scope)
        async let b = second.receiveReviewedText(bytes, identity: scope)
        _ = try await (a, b)
        let all = try await first.list(); XCTAssertEqual(all.count, 2)
    }
    func testMissingReceiptTableDoesNotReseedOnReopen() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path)
        let scope = try await identity(store)
        try sql(path, "DROP TABLE text_receive_receipts")
        let reopened = try SQLiteConversationStore(url: path)
        do { _ = try await reopened.receiveReviewedText(try payload([Conversation()]), identity: scope); XCTFail("Missing receipts silently recreated") } catch { }
        let all = try await reopened.list(); XCTAssertTrue(all.isEmpty)
    }
    func testMissingReceiptTableStillAllowsIndividualAndAllHistoryErasure() async throws {
        for eraseAll in [false, true] {
            let path = url(), store = try SQLiteConversationStore(url: path)
            let value = Conversation(title: "Private"), scope = try await identity(store)
            let bytes = try payload([value])
            _ = try await store.receiveReviewedText(bytes, identity: scope)
            try await store.saveMemory(MemoryNote(content: "Private memory"))
            try sql(path, "DROP TABLE text_receive_receipts")
            let reopened = try SQLiteConversationStore(url: path)
            if eraseAll { try await reopened.deleteAll() }
            else { try await reopened.delete(id: value.id) }
            let all = try await reopened.list(); XCTAssertTrue(all.isEmpty)
            let notes = try await reopened.memories(); XCTAssertEqual(notes.count, eraseAll ? 0 : 1)
            let newScope = try await identity(reopened)
            for attemptedScope in [scope, newScope] {
                do { _ = try await reopened.receiveReviewedText(bytes, identity: attemptedScope); XCTFail("Missing receipts allowed receive") } catch { }
            }
        }
    }

    func testMissingEpochRowStillAllowsErasureAndReceiveStaysClosed() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path)
        let value = Conversation(title: "Private"), scope = try await identity(store)
        let bytes = try payload([value])
        _ = try await store.receiveReviewedText(bytes, identity: scope)
        try sql(path, "DELETE FROM text_receive_epoch")
        try await store.deleteAll()
        let all = try await store.list(); XCTAssertTrue(all.isEmpty)
        do { _ = try await store.receiveReviewedText(bytes, identity: scope); XCTFail("Missing epoch allowed receive") } catch { }
    }

    #if os(Linux)
    func testRepeatedInitializationMigrationFailureDoesNotLeakDatabaseDescriptors() async throws {
        let path = url()
        _ = try SQLiteConversationStore(url: path)
        // Existing receipt schema with absent epoch causes the migration to fail.
        try sql(path, "DROP TABLE text_receive_epoch")
        func descriptors() -> Int {
            let directory = URL(fileURLWithPath: "/proc/self/fd")
            return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?.filter {
                (try? FileManager.default.destinationOfSymbolicLink(atPath: $0.path))?.hasPrefix(path.path) == true
            }.count ?? 0
        }
        let before = descriptors()
        for _ in 0..<20 {
            do { _ = try SQLiteConversationStore(url: path); XCTFail("Invalid migration accepted") } catch { }
        }
        XCTAssertEqual(descriptors(), before)
    }
    #endif

    func testMissingEpochDoesNotReseedOnReopen() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path)
        let scope = try await identity(store)
        try sql(path, "DELETE FROM text_receive_epoch")
        let reopened = try SQLiteConversationStore(url: path)
        do { _ = try await reopened.receiveReviewedText(try payload([Conversation()]), identity: scope); XCTFail("Missing epoch silently recreated") } catch { }
    }
    func testReceiptCapacityFailsWithoutEvictionOrContentWrite() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path)
        let scope = try await identity(store)
        try sql(path, "INSERT INTO text_receive_receipts VALUES ('synthetic', X'01', 'synthetic', zeroblob(50000000), X'01')")
        do { _ = try await store.receiveReviewedText(try payload([Conversation()]), identity: scope); XCTFail("Over-capacity accepted") } catch { }
        let all = try await store.list(); XCTAssertTrue(all.isEmpty)
    }
    func testManualImportStillCopiesOnRepeatedConflicts() async throws {
        let store = try SQLiteConversationStore(url: url()), local = Conversation(title: "Local")
        try await store.save(local)
        var remote = local; remote.title = "Remote"
        let bytes = try payload([remote])
        _ = try await store.importData(bytes, policy: .keepBoth)
        _ = try await store.importData(bytes, policy: .keepBoth)
        let all = try await store.list(); XCTAssertEqual(all.count, 3)
    }
}
