import XCTest
import SQLite3
@testable import JarvisEVO

final class TextSendOutboxTests: XCTestCase {
    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite") }
    private func chat(_ title: String = "Selected") -> Conversation { Conversation(title: title, messages: [ChatMessage(role: .user, content: "Reviewed text")]) }
    private func stage(_ store: SQLiteConversationStore, _ snapshot: ReviewedTextSnapshot, epoch: UUID = UUID()) async throws -> StagedTextSend {
        try await store.stageTextSend(snapshot, senderCertificateSHA256: Data(repeating: 1, count: 32), peerCertificateSHA256: Data(repeating: 2, count: 32), pairingGeneration: UUID(), receiverEpoch: epoch)
    }
    private func sql(_ path: URL, _ query: String) throws {
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, query, nil, nil, nil), SQLITE_OK)
    }
    func testSelectedExactBytesAndBothIdentitiesSurviveReopenAndLocalEdit() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path)
        var selected = chat(); let excluded = chat("Excluded")
        try await store.save(selected); try await store.save(excluded)
        try await store.saveMemory(MemoryNote(content: "Not selected"))
        let snapshot = try await store.exportTextSnapshot(ids: [selected.id])
        let draft = try await stage(store, snapshot)
        selected.title = "Later edit"; try await store.save(selected)
        let reopened = try SQLiteConversationStore(url: path)
        let loaded = try await reopened.textSend(id: draft.identity.transfer)
        XCTAssertEqual(loaded?.payload, snapshot.data); XCTAssertEqual(loaded?.identity, draft.identity)
        let decoded = try JSONDecoder().decode(ConversationBackup.self, from: XCTUnwrap(loaded).payload)
        XCTAssertEqual(decoded.conversations.map(\.title), ["Selected"]); XCTAssertTrue(decoded.memories.isEmpty)
        XCTAssertEqual(draft.identity.receiveIdentity.peerCertificateSHA256, draft.identity.senderCertificateSHA256)
        XCTAssertNotEqual(draft.identity.receiveIdentity.peerCertificateSHA256, draft.identity.receiverCertificateSHA256)
        let pending = try await reopened.pendingTextSendIDs(); XCTAssertEqual(pending, [draft.identity.transfer])
    }
    func testSelectionChangedBeforeStagingRejectsWithoutDraft() async throws {
        let store = try SQLiteConversationStore(url: url()); var value = chat()
        try await store.save(value)
        let snapshot = try await store.exportTextSnapshot(ids: [value.id])
        value.title = "Changed"; try await store.save(value)
        do { _ = try await stage(store, snapshot); XCTFail("Stale review staged") } catch { }
        try await store.delete(id: value.id)
        do { _ = try await stage(store, snapshot); XCTFail("Deleted selection staged") } catch { }
        let pending = try await store.pendingTextSendIDs(); XCTAssertTrue(pending.isEmpty)
    }
    func testTwoDatabasesRecoverLostReceiptWithoutDuplicateConflictCopy() async throws {
        let senderPath = url(), receiverPath = url()
        let sender = try SQLiteConversationStore(url: senderPath), receiver = try SQLiteConversationStore(url: receiverPath)
        let original = chat("Sender version"); var local = original; local.title = "Receiver edit"
        try await sender.save(original); try await receiver.save(local)
        let draft = try await stage(sender, sender.exportTextSnapshot(ids: [original.id]), epoch: receiver.textReceiveEpoch())
        let first = try await receiver.receiveReviewedText(draft.payload, identity: draft.identity.receiveIdentity)
        XCTAssertEqual(first.copiedConversations, 1)
        // Simulate a lost acknowledgement by reopening both stores before the sender records it.
        let reopenedSender = try SQLiteConversationStore(url: senderPath), reopenedReceiver = try SQLiteConversationStore(url: receiverPath)
        let pending = try await reopenedSender.pendingTextSendIDs(); XCTAssertEqual(pending, [draft.identity.transfer])
        let loaded = try await reopenedSender.textSend(id: draft.identity.transfer)
        let retry = try XCTUnwrap(loaded)
        let second = try await reopenedReceiver.receiveReviewedText(retry.payload, identity: retry.identity.receiveIdentity)
        XCTAssertEqual(second.copiedConversations, 1)
        try await reopenedSender.recordTextDeliveryReceipt(identity: retry.identity, payload: retry.payload)
        let all = try await reopenedReceiver.list(); XCTAssertEqual(Set(all.map(\.title)), ["Sender version", "Receiver edit"])
        XCTAssertEqual(all.count, 2)
        let remaining = try await reopenedSender.pendingTextSendIDs(); XCTAssertTrue(remaining.isEmpty)
        let delivered = try await reopenedSender.textSend(id: draft.identity.transfer); XCTAssertEqual(delivered?.delivered, true)
    }
    func testReceiptRejectsChangedBytesRecipientSenderPairAndEpoch() async throws {
        let store = try SQLiteConversationStore(url: url()), value = chat()
        try await store.save(value)
        let draft = try await stage(store, store.exportTextSnapshot(ids: [value.id]))
        let i = draft.identity
        let alternatives = [
            TextSendIdentity(receiverEpoch: UUID(), transfer: i.transfer, senderCertificateSHA256: i.senderCertificateSHA256, receiverCertificateSHA256: i.receiverCertificateSHA256, pairingGeneration: i.pairingGeneration),
            TextSendIdentity(receiverEpoch: i.receiverEpoch, transfer: i.transfer, senderCertificateSHA256: i.receiverCertificateSHA256, receiverCertificateSHA256: i.senderCertificateSHA256, pairingGeneration: i.pairingGeneration),
            TextSendIdentity(receiverEpoch: i.receiverEpoch, transfer: i.transfer, senderCertificateSHA256: i.senderCertificateSHA256, receiverCertificateSHA256: i.receiverCertificateSHA256, pairingGeneration: UUID())]
        for altered in alternatives {
            do { try await store.recordTextDeliveryReceipt(identity: altered, payload: draft.payload); XCTFail("Changed scope accepted") } catch { }
        }
        do { try await store.recordTextDeliveryReceipt(identity: i, payload: Data("changed".utf8)); XCTFail("Changed bytes accepted") } catch { }
        let loaded = try await store.textSend(id: i.transfer); XCTAssertEqual(loaded?.delivered, false)
    }
    func testDeliveryReceiptIsIdempotentAndSurvivesReopen() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path), value = chat()
        try await store.save(value)
        let draft = try await stage(store, store.exportTextSnapshot(ids: [value.id]))
        try await store.recordTextDeliveryReceipt(identity: draft.identity, payload: draft.payload)
        let reopened = try SQLiteConversationStore(url: path)
        try await reopened.recordTextDeliveryReceipt(identity: draft.identity, payload: draft.payload)
        let pending = try await reopened.pendingTextSendIDs(); XCTAssertTrue(pending.isEmpty)
        let loaded = try await reopened.textSend(id: draft.identity.transfer); XCTAssertEqual(loaded?.payload, draft.payload)
    }
    func testFailedReceiptUpdateRemainsPendingAndRetryWorks() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path), value = chat()
        try await store.save(value)
        let draft = try await stage(store, store.exportTextSnapshot(ids: [value.id]))
        try sql(path, "CREATE TRIGGER reject_delivery BEFORE UPDATE ON text_send_outbox BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        do { try await store.recordTextDeliveryReceipt(identity: draft.identity, payload: draft.payload); XCTFail("Update failure accepted") } catch { }
        let pending = try await store.pendingTextSendIDs(); XCTAssertEqual(pending, [draft.identity.transfer])
        try sql(path, "DROP TRIGGER reject_delivery")
        try await store.recordTextDeliveryReceipt(identity: draft.identity, payload: draft.payload)
    }
    func testDiscardDoesNotDeleteConversationAndRejectsLateReceipt() async throws {
        let store = try SQLiteConversationStore(url: url()), value = chat()
        try await store.save(value)
        let draft = try await stage(store, store.exportTextSnapshot(ids: [value.id]))
        try await store.discardTextSend(id: draft.identity.transfer)
        do { try await store.recordTextDeliveryReceipt(identity: draft.identity, payload: draft.payload); XCTFail("Canceled draft resurrected") } catch { }
        let original = try await store.load(id: value.id); XCTAssertEqual(original, value)
        let loaded = try await store.textSend(id: draft.identity.transfer); XCTAssertNil(loaded)
    }
    func testHistoryErasureClearsPendingAndDeliveredDraftText() async throws {
        for eraseAll in [false, true] {
            let store = try SQLiteConversationStore(url: url()), value = chat()
            try await store.save(value)
            let snapshot = try await store.exportTextSnapshot(ids: [value.id])
            let pending = try await stage(store, snapshot), delivered = try await stage(store, snapshot)
            try await store.recordTextDeliveryReceipt(identity: delivered.identity, payload: delivered.payload)
            if eraseAll { try await store.deleteAll() } else { try await store.delete(id: value.id) }
            for draft in [pending, delivered] {
                let loaded = try await store.textSend(id: draft.identity.transfer); XCTAssertNil(loaded)
                do { try await store.recordTextDeliveryReceipt(identity: draft.identity, payload: draft.payload); XCTFail("Erased draft accepted") } catch { }
            }
        }
    }
    func testErasureFailurePreservesContentAndOutboxTogether() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path), value = chat()
        try await store.save(value)
        let draft = try await stage(store, store.exportTextSnapshot(ids: [value.id]))
        try sql(path, "CREATE TRIGGER reject_outbox_erase BEFORE DELETE ON text_send_outbox BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        do { try await store.delete(id: value.id); XCTFail("Erase failure accepted") } catch { }
        let loaded = try await store.load(id: value.id); XCTAssertEqual(loaded, value)
        let pending = try await store.pendingTextSendIDs(); XCTAssertEqual(pending, [draft.identity.transfer])
    }
    func testMissingOutboxDoesNotBlockUserErasure() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path), value = chat()
        try await store.save(value)
        try sql(path, "DROP TABLE text_send_outbox")
        try await store.deleteAll()
        let all = try await store.list(); XCTAssertTrue(all.isEmpty)
    }
    func testCapacityAndInsertFailureDoNotStageOrModifySelection() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path), value = chat()
        try await store.save(value)
        let snapshot = try await store.exportTextSnapshot(ids: [value.id])
        try sql(path, "CREATE TRIGGER reject_stage BEFORE INSERT ON text_send_outbox BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        do { _ = try await stage(store, snapshot); XCTFail("Insert failure accepted") } catch { }
        try sql(path, "DROP TRIGGER reject_stage")
        let pending = try await store.pendingTextSendIDs(); XCTAssertTrue(pending.isEmpty)
        try sql(path, "INSERT INTO text_send_outbox VALUES ('synthetic', X'01', X'02', 'synthetic', 'synthetic', zeroblob(50000000), 1)")
        do { _ = try await stage(store, snapshot); XCTFail("Capacity exceeded") } catch { }
        let original = try await store.load(id: value.id); XCTAssertEqual(original, value)
    }
    func testChangedStreamingOrOversizedSourceRejectsBeforeStaging() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path)
        var value = chat(); try await store.save(value)
        let snapshot = try await store.exportTextSnapshot(ids: [value.id])
        value.messages[0].state = .streaming; try await store.save(value)
        do { _ = try await stage(store, snapshot); XCTFail("Streaming source change accepted") } catch { }
        try sql(path, "UPDATE conversations SET payload=zeroblob(5000001)")
        do { _ = try await stage(store, snapshot); XCTFail("Oversized changed source accepted") } catch { }
        let pending = try await store.pendingTextSendIDs(); XCTAssertTrue(pending.isEmpty)
    }
    func testReceiptCountCapacityRejectsWithoutEvictingExistingRows() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path), value = chat()
        try await store.save(value)
        let snapshot = try await store.exportTextSnapshot(ids: [value.id])
        try sql(path, "WITH RECURSIVE fixture(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM fixture WHERE i<10000) INSERT INTO text_send_outbox SELECT CAST(i AS TEXT), X'01', X'02', 'fixture', 'fixture', X'01', 1 FROM fixture")
        do { _ = try await stage(store, snapshot); XCTFail("Receipt count capacity exceeded") } catch { }
        try sql(path, "CREATE TRIGGER prove_rows_remain BEFORE DELETE ON text_send_outbox BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        // If capacity checking had evicted rows, this attempted cleanup would not fail.
        do { try await store.deleteAll(); XCTFail("Existing rows were silently evicted") } catch { }
    }
    func testCorruptPayloadOrDeliveryStorageTypeFailsClosed() async throws {
        for corruption in ["PRAGMA ignore_check_constraints=ON; UPDATE text_send_outbox SET delivered=0.5", "UPDATE text_send_outbox SET payload=CAST('{}' AS BLOB)"] {
            let path = url(), store = try SQLiteConversationStore(url: path), value = chat()
            try await store.save(value)
            let draft = try await stage(store, store.exportTextSnapshot(ids: [value.id]))
            try sql(path, corruption)
            do { _ = try await store.textSend(id: draft.identity.transfer); XCTFail("Corrupt draft accepted") } catch { }
            do { try await store.recordTextDeliveryReceipt(identity: draft.identity, payload: draft.payload); XCTFail("Corrupt draft acknowledged") } catch { }
        }
    }
    func testHiddenUnknownJSONFieldCannotBeReturnedForSending() async throws {
        let path = url(), store = try SQLiteConversationStore(url: path), value = chat()
        try await store.save(value)
        let draft = try await stage(store, store.exportTextSnapshot(ids: [value.id]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.payload) as? [String: Any])
        object["unreviewed"] = "Hidden data"
        let changed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var db: OpaquePointer?; sqlite3_open(path.path, &db)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?; sqlite3_prepare_v2(db, "UPDATE text_send_outbox SET payload=?", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        _ = changed.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32(changed.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        do { _ = try await store.textSend(id: draft.identity.transfer); XCTFail("Hidden JSON field accepted") } catch { }
    }
    func testWrongPinLengthAndSelfDestinationReject() async throws {
        let store = try SQLiteConversationStore(url: url()), value = chat()
        try await store.save(value)
        let snapshot = try await store.exportTextSnapshot(ids: [value.id])
        for peer in [Data(), Data(repeating: 1, count: 32)] {
            do { _ = try await store.stageTextSend(snapshot, senderCertificateSHA256: Data(repeating: 1, count: 32), peerCertificateSHA256: peer, pairingGeneration: UUID(), receiverEpoch: UUID()); XCTFail("Invalid pair accepted") } catch { }
        }
    }
}
