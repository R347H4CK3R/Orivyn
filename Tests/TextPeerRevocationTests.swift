import XCTest
import SQLite3
@testable import JarvisEVO

final class TextPeerRevocationTests: XCTestCase {
    private let peer=Data(repeating:2,count:32), local=Data(repeating:1,count:32)
    private func path()->URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite") }
    private func sql(_ path:URL,_ query:String) throws { var db:OpaquePointer?;XCTAssertEqual(sqlite3_open(path.path,&db),SQLITE_OK);defer{sqlite3_close(db)};XCTAssertEqual(sqlite3_exec(db,query,nil,nil,nil),SQLITE_OK) }
    private func count(_ path:URL,_ table:String) throws -> Int {var db:OpaquePointer?,s:OpaquePointer?;XCTAssertEqual(sqlite3_open(path.path,&db),SQLITE_OK);defer{sqlite3_finalize(s);sqlite3_close(db)};XCTAssertEqual(sqlite3_prepare_v2(db,"SELECT COUNT(*) FROM \(table)",-1,&s,nil),SQLITE_OK);XCTAssertEqual(sqlite3_step(s),SQLITE_ROW);return Int(sqlite3_column_int64(s,0))}
    private func stage(_ store:SQLiteConversationStore,_ snapshot:ReviewedTextSnapshot,_ generation:UUID) async throws -> StagedTextSend { try await store.stageTextSend(snapshot,senderCertificateSHA256:local,peerCertificateSHA256:peer,pairingGeneration:generation,receiverEpoch:UUID()) }
    func testRevocationSurvivesReopenAndBlocksReceiveStageAndLateReceipt() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),generation=UUID(),chat=Conversation(title:"Selected")
        try await store.save(chat);let snapshot=try await store.exportTextSnapshot(ids:[chat.id]);let draft=try await stage(store,snapshot,generation)
        try await store.recordTextDeliveryReceipt(identity:draft.identity,payload:draft.payload)
        let received=ReviewedTextReceiveIdentity(epoch:try await store.textReceiveEpoch(),transfer:UUID(),peerCertificateSHA256:peer,pairingGeneration:generation)
        _=try await store.receiveReviewedText(snapshot.data,identity:received)
        try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation)
        let reopened=try SQLiteConversationStore(url:url)
        let revoked=try await reopened.isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:generation);XCTAssertTrue(revoked)
        XCTAssertEqual(try count(url,"text_send_outbox"),0);XCTAssertEqual(try count(url,"text_receive_receipts"),0)
        do {_=try await stage(reopened,snapshot,generation);XCTFail("Revoked staging")}catch{}
        do {_=try await reopened.receiveReviewedText(snapshot.data,identity:received);XCTFail("Revoked receive retry")}catch{}
        do {try await reopened.recordTextDeliveryReceipt(identity:draft.identity,payload:draft.payload);XCTFail("Revoked late receipt")}catch{}
        let retained=try await reopened.load(id:chat.id);XCTAssertEqual(retained?.title,chat.title)
    }
    func testRevocationIsIdempotentSelectiveAndDoesNotAuthorizeNewGeneration() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),old=UUID(),fresh=UUID(),chat=Conversation(title:"Selected")
        try await store.save(chat);let snapshot=try await store.exportTextSnapshot(ids:[chat.id])
        _=try await stage(store,snapshot,old);let other=try await stage(store,snapshot,fresh)
        try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:old)
        try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:old)
        XCTAssertEqual(try count(url,"text_peer_revocations"),1)
        let pending=try await store.pendingTextSendIDs();XCTAssertEqual(pending,[other.identity.transfer])
        let newRevoked=try await store.isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:fresh);XCTAssertFalse(newRevoked) // Not revoked is NOT authenticated/approved.
        try await store.deleteAll()
        let remains=try await store.isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:old);XCTAssertTrue(remains)
    }
    func testFailedMetadataCleanupRollsBackRevocationAndKeepsDraft() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),generation=UUID(),chat=Conversation(title:"Selected")
        try await store.save(chat);let snapshot=try await store.exportTextSnapshot(ids:[chat.id]);let draft=try await stage(store,snapshot,generation)
        try sql(url,"CREATE TRIGGER prevent_revoke BEFORE DELETE ON text_send_outbox BEGIN SELECT RAISE(ABORT,'fixture'); END")
        do {try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation);XCTFail("Partial revoke committed")}catch{}
        let revoked=try await store.isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:generation);XCTAssertFalse(revoked)
        let still=try await store.textSend(id:draft.identity.transfer);XCTAssertNotNil(still)
    }
    func testMissingRevocationMetadataFailsClosedButLocalErasureStillWorks() async throws {
        for table in ["text_peer_revocations","text_peer_revocation_state"] {
            let url=path(),store=try SQLiteConversationStore(url:url),generation=UUID(),chat=Conversation(title:"Local")
            try await store.save(chat);let snapshot=try await store.exportTextSnapshot(ids:[chat.id])
            try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation)
            try sql(url,"DROP TABLE \(table)")
            let reopened=try SQLiteConversationStore(url:url)
            do {_=try await reopened.isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:generation);XCTFail("Lost metadata silently healed")}catch{}
            do {_=try await stage(reopened,snapshot,UUID());XCTFail("Unknown revocation state staged")}catch{}
            try await reopened.deleteAll();let remaining=try await reopened.list();XCTAssertTrue(remaining.isEmpty)
        }
    }
}
extension TextPeerRevocationTests {
    func testLossOfBothTablesDoesNotReclassifyMigratedDatabaseAsLegacy() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),generation=UUID()
        try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation)
        try sql(url,"DROP TABLE text_peer_revocation_state; DROP TABLE text_peer_revocations")
        let reopened=try SQLiteConversationStore(url:url)
        do {_=try await reopened.isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:generation);XCTFail("Both lost tables revived peer")}catch{}
        try await reopened.save(Conversation(title:"Local still usable"));try await reopened.deleteAll()
    }
    func testLegacyMigrationPreservesExistingOutboxAndReceiptScopes() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),generation=UUID(),chat=Conversation(title:"Legacy")
        try await store.save(chat);let snapshot=try await store.exportTextSnapshot(ids:[chat.id]);let draft=try await stage(store,snapshot,generation)
        let receive=ReviewedTextReceiveIdentity(epoch:try await store.textReceiveEpoch(),transfer:UUID(),peerCertificateSHA256:peer,pairingGeneration:generation)
        _=try await store.receiveReviewedText(snapshot.data,identity:receive)
        // Reconstruct the pre-revocation schema; no prior revocation exists here.
        try sql(url,"DROP TABLE text_peer_revocation_state; DROP TABLE text_peer_revocations; PRAGMA user_version=0")
        let migrated=try SQLiteConversationStore(url:url)
        let loaded=try await migrated.textSend(id:draft.identity.transfer);XCTAssertEqual(loaded?.payload,draft.payload)
        _=try await migrated.receiveReviewedText(snapshot.data,identity:receive)
        XCTAssertEqual(try count(url,"text_receive_receipts"),1)
        let chats=try await migrated.list();XCTAssertEqual(chats.count,1)
        try await migrated.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation)
        let revoked=try await migrated.isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:generation);XCTAssertTrue(revoked)
    }
    func testConcurrentReceiveAndRevocationHaveOneSerializedCommitBoundary() async throws {
        let url=path(),first=try SQLiteConversationStore(url:url),second=try SQLiteConversationStore(url:url),generation=UUID()
        let receive=ReviewedTextReceiveIdentity(epoch:try await first.textReceiveEpoch(),transfer:UUID(),peerCertificateSHA256:peer,pairingGeneration:generation)
        let payload=try JSONEncoder().encode(ConversationBackup(conversations:[Conversation(title:"Remote")],memories:[]))
        async let imported:Bool = { do {_=try await second.receiveReviewedText(payload,identity:receive);return true}catch{return false} }()
        try await first.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation)
        let applied=await imported
        let chats=try await first.list();XCTAssertEqual(chats.count,applied ? 1 : 0)
        XCTAssertEqual(try count(url,"text_receive_receipts"),0)
        do {_=try await second.receiveReviewedText(payload,identity:receive);XCTFail("Post-revoke retry applied")}catch{}
        let revoked=try await second.isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:generation);XCTAssertTrue(revoked)
    }
    func testFullRevocationStorageRejectsNewScopeWithoutEvictionOrPartialCleanup() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),generation=UUID(),chat=Conversation(title:"Pending")
        try await store.save(chat);let snapshot=try await store.exportTextSnapshot(ids:[chat.id]);let draft=try await stage(store,snapshot,generation)
        try sql(url,"WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<10000) INSERT INTO text_peer_revocations(peer,generation) SELECT zeroblob(32),printf('00000000-0000-0000-0000-%012X',x) FROM n")
        do {try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation);XCTFail("Capacity silently evicted tombstone")}catch{}
        XCTAssertEqual(try count(url,"text_peer_revocations"),10000)
        let retained=try await store.textSend(id:draft.identity.transfer);XCTAssertNotNil(retained)
        try await store.revokeTextPeer(peerCertificateSHA256:Data(repeating:0,count:32),pairingGeneration:UUID(uuidString:"00000000-0000-0000-0000-000000000001")!)
        XCTAssertEqual(try count(url,"text_peer_revocations"),10000)
    }
}

extension TextPeerRevocationTests {
    func testReceiptCleanupFailureRollsBackAlreadyDeletedOutboxAndTombstone() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),generation=UUID(),chat=Conversation(title:"Atomic")
        try await store.save(chat);let snapshot=try await store.exportTextSnapshot(ids:[chat.id]);let draft=try await stage(store,snapshot,generation)
        let receive=ReviewedTextReceiveIdentity(epoch:try await store.textReceiveEpoch(),transfer:UUID(),peerCertificateSHA256:peer,pairingGeneration:generation)
        _=try await store.receiveReviewedText(snapshot.data,identity:receive)
        try sql(url,"CREATE TRIGGER prevent_receipt_cleanup BEFORE DELETE ON text_receive_receipts BEGIN SELECT RAISE(ABORT,'fixture'); END")
        do {try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation);XCTFail("Partial cleanup committed")}catch{}
        XCTAssertEqual(try count(url,"text_receive_receipts"),1)
        let retained=try await store.textSend(id:draft.identity.transfer);XCTAssertNotNil(retained)
        let revoked=try await store.isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:generation);XCTAssertFalse(revoked)
    }
    func testLostMarkerAndUnknownHeaderVersionPauseSyncWithoutPreventingErasure() async throws {
        for damage in ["DELETE FROM text_peer_revocation_state","PRAGMA user_version=99"] {
            let url=path(),store=try SQLiteConversationStore(url:url),chat=Conversation(title:"Local")
            try await store.save(chat);let snapshot=try await store.exportTextSnapshot(ids:[chat.id]);try sql(url,damage)
            let reopened=try SQLiteConversationStore(url:url)
            let receive=ReviewedTextReceiveIdentity(epoch:try await reopened.textReceiveEpoch(),transfer:UUID(),peerCertificateSHA256:peer,pairingGeneration:UUID())
            do {_=try await reopened.receiveReviewedText(snapshot.data,identity:receive);XCTFail("Damaged metadata accepted receive")}catch{}
            do {_=try await reopened.pendingTextSendIDs();XCTFail("Damaged metadata enumerated recovery drafts")}catch{}
            try await reopened.deleteAll();let chats=try await reopened.list();XCTAssertTrue(chats.isEmpty)
        }
    }
}
extension TextPeerRevocationTests {
    func testFailedLegacyMigrationRollsBackNewMetadataWithoutLosingExistingDraft() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),generation=UUID(),chat=Conversation(title:"Legacy migration")
        try await store.save(chat);let snapshot=try await store.exportTextSnapshot(ids:[chat.id]);let draft=try await stage(store,snapshot,generation)
        try sql(url,"DROP TABLE text_peer_revocation_state; DROP TABLE text_peer_revocations; PRAGMA user_version=0; CREATE VIEW text_peer_revocations AS SELECT 1 AS invalid")
        XCTAssertThrowsError(try SQLiteConversationStore(url:url))
        XCTAssertEqual(try count(url,"sqlite_master WHERE name='text_peer_revocation_state'"),0)
        let local=try await store.load(id:chat.id);XCTAssertEqual(local?.title,chat.title)
        // Explicit fixture repair, never an automatic production recovery path.
        try sql(url,"DROP VIEW text_peer_revocations")
        let repaired=try SQLiteConversationStore(url:url)
        let retained=try await repaired.textSend(id:draft.identity.transfer);XCTAssertEqual(retained?.payload,draft.payload)
    }
}
