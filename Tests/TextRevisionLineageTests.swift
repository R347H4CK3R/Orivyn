import XCTest
import SQLite3
@testable import JarvisEVO

final class TextRevisionLineageTests: XCTestCase {
    private let peer=Data(repeating:7,count:32),generation=UUID()
    private func path()->URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite") }
    private func scope(_ store:SQLiteConversationStore,transfer:UUID=UUID()) async throws -> ReviewedTextReceiveIdentity { .init(epoch:try await store.textReceiveEpoch(),transfer:transfer,peerCertificateSHA256:peer,pairingGeneration:generation) }
    private func envelope(_ incoming:Conversation,base:Conversation?=nil) throws -> Data { try TextRevisionEnvelope(records:[.init(base:base,incoming:incoming)]).data }
    private func sql(_ path:URL,_ query:String) throws { var db:OpaquePointer?;XCTAssertEqual(sqlite3_open(path.path,&db),SQLITE_OK);defer{sqlite3_close(db)};XCTAssertEqual(sqlite3_exec(db,query,nil,nil,nil),SQLITE_OK) }
    func testKnownExactBaseAdvancesAfterReopenWithoutConflictCopies() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),original=Conversation(title:"Remote v1")
        let first=try await store.receiveReviewedTextRevisions(envelope(original),identity:scope(store))
        XCTAssertEqual(first.records[0].disposition,.inserted)
        var next=original;next.title="Remote v2"
        let reopened=try SQLiteConversationStore(url:url)
        let second=try await reopened.receiveReviewedTextRevisions(envelope(next,base:original),identity:scope(reopened))
        XCTAssertEqual(second.records[0].disposition,.advanced);XCTAssertEqual(second.records[0].localID,original.id)
        let all=try await reopened.list();XCTAssertEqual(all.map(\.title),["Remote v2"])
    }
    func testLocalEditConflictsAndFutureRevisionAdvancesOnlyConflictCopy() async throws {
        let store=try SQLiteConversationStore(url:path()),original=Conversation(title:"Base")
        _=try await store.receiveReviewedTextRevisions(envelope(original),identity:scope(store))
        var local=original;local.title="My edit";try await store.save(local)
        var remote=original;remote.title="Their edit"
        let conflict=try await store.receiveReviewedTextRevisions(envelope(remote,base:original),identity:scope(store))
        XCTAssertEqual(conflict.records[0].disposition,.conflict);XCTAssertEqual(conflict.records[0].preservedLocalID,original.id)
        let mapped=conflict.records[0].localID;XCTAssertNotEqual(mapped,original.id)
        var later=remote;later.title="Their next edit"
        let advanced=try await store.receiveReviewedTextRevisions(envelope(later,base:remote),identity:scope(store))
        XCTAssertEqual(advanced.records[0].localID,mapped);XCTAssertEqual(advanced.records[0].disposition,.advanced)
        let all=try await store.list();XCTAssertEqual(Set(all.map(\.title)),["My edit","Their next edit"])
    }
    func testUnknownMissingAndStaleAncestryRejectWithoutChangingHistory() async throws {
        let store=try SQLiteConversationStore(url:path()),base=Conversation(title:"Base")
        var remote=base;remote.title="Next"
        do {_=try await store.receiveReviewedTextRevisions(envelope(remote,base:base),identity:scope(store));XCTFail("Unknown ancestry accepted")}catch{}
        _=try await store.receiveReviewedTextRevisions(envelope(base),identity:scope(store))
        do {_=try await store.receiveReviewedTextRevisions(envelope(remote),identity:scope(store));XCTFail("Missing ancestry accepted")}catch{}
        _=try await store.receiveReviewedTextRevisions(envelope(remote,base:base),identity:scope(store))
        do {_=try await store.receiveReviewedTextRevisions(envelope(base,base:base),identity:scope(store));XCTFail("Out-of-order ancestry accepted")}catch{}
        let all=try await store.list();XCTAssertEqual(all.map(\.title),["Next"])
    }
    func testReceiptReplayIsExactNonmutatingAndIncludesAncestry() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),base=Conversation(title:"Base")
        let identity=try await scope(store),bytes=try envelope(base)
        let first=try await store.receiveReviewedTextRevisions(bytes,identity:identity)
        var local=base;local.title="Local edit";try await store.save(local)
        let reopened=try SQLiteConversationStore(url:url)
        let replay=try await reopened.receiveReviewedTextRevisions(bytes,identity:identity);XCTAssertEqual(first,replay)
        do {_=try await reopened.receiveReviewedTextRevisions(envelope(base,base:base),identity:identity);XCTFail("Changed ancestry replay accepted")}catch{}
        let actual=try await reopened.load(id:base.id);XCTAssertEqual(actual?.title,"Local edit")
    }
    func testCanonicalEnvelopeRejectsUnknownFieldsDuplicateKeysAndNoncompleteContent() throws {
        let base=Conversation(title:"Valid"),bytes=try envelope(base)
        XCTAssertEqual(try TextRevisionEnvelope.decodeCanonical(bytes).data,bytes)
        let text=String(decoding:bytes,as:UTF8.self)
        for altered in [" "+text,text.replacingOccurrences(of:"{",with:"{\"extra\":1,",range:text.startIndex..<text.index(after:text.startIndex)),text.replacingOccurrences(of:"\"format\":",with:"\"format\":\"ignored\",\"format\":")] {XCTAssertThrowsError(try TextRevisionEnvelope.decodeCanonical(Data(altered.utf8)))}
        var unfinished=base;unfinished.messages=[ChatMessage(role:.assistant,content:"partial",state:.streaming)]
        XCTAssertThrowsError(try envelope(unfinished));XCTAssertThrowsError(try TextRevisionEnvelope.decodeCanonical(Data(repeating:0,count:5_000_001)))
    }
}

extension TextRevisionLineageTests {
    func testFirstContactCannotAdoptIdenticalExistingLocalRow() async throws {
        let store=try SQLiteConversationStore(url:path()),original=Conversation(title:"Local original")
        try await store.save(original)
        let first=try await store.receiveReviewedTextRevisions(envelope(original),identity:scope(store))
        XCTAssertEqual(first.records[0].disposition,.conflict)
        XCTAssertNotEqual(first.records[0].localID,original.id)
        var next=original;next.title="Remote successor"
        _=try await store.receiveReviewedTextRevisions(envelope(next,base:original),identity:scope(store))
        let preserved=try await store.load(id:original.id);XCTAssertEqual(preserved?.title,"Local original")
    }
    func testNoOpDoesNotAdoptLocalEditsAsRemoteBase() async throws {
        let store=try SQLiteConversationStore(url:path()),base=Conversation(title:"Base")
        _=try await store.receiveReviewedTextRevisions(envelope(base),identity:scope(store))
        var local=base;local.title="Local edit";try await store.save(local)
        let noOp=try await store.receiveReviewedTextRevisions(envelope(base,base:base),identity:scope(store))
        XCTAssertEqual(noOp.records[0].disposition,.unchanged)
        var next=base;next.title="Remote edit"
        let conflict=try await store.receiveReviewedTextRevisions(envelope(next,base:base),identity:scope(store))
        XCTAssertEqual(conflict.records[0].disposition,.conflict)
        let all=try await store.list();XCTAssertEqual(Set(all.map(\.title)),["Local edit","Remote edit"])
    }
    func testMissingMappedTargetRejectsWithoutResurrection() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),base=Conversation(title:"Base")
        _=try await store.receiveReviewedTextRevisions(envelope(base),identity:scope(store))
        try sql(url,"DELETE FROM conversations")
        var next=base;next.title="Later"
        do {_=try await store.receiveReviewedTextRevisions(envelope(next,base:base),identity:scope(store));XCTFail("Deleted row resurrected")}catch{}
        let all=try await store.list();XCTAssertTrue(all.isEmpty)
    }
    func testLineageWriteFailureRollsBackContentAndReceiptBeforeRetry() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),base=Conversation(title:"Atomic")
        let identity=try await scope(store),payload=try envelope(base)
        try sql(url,"CREATE TRIGGER reject_lineage BEFORE INSERT ON text_revision_lineage BEGIN SELECT RAISE(ABORT,'fixture'); END")
        do {_=try await store.receiveReviewedTextRevisions(payload,identity:identity);XCTFail("Partial revision committed")}catch{}
        let empty=try await store.list();XCTAssertTrue(empty.isEmpty)
        try sql(url,"DROP TRIGGER reject_lineage")
        let retry=try await store.receiveReviewedTextRevisions(payload,identity:identity)
        XCTAssertEqual(retry.records[0].disposition,.inserted)
    }
    func testRevocationAndErasureInvalidateRevisionRetries() async throws {
        let store=try SQLiteConversationStore(url:path()),base=Conversation(title:"Received")
        let identity=try await scope(store),payload=try envelope(base)
        _=try await store.receiveReviewedTextRevisions(payload,identity:identity)
        try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation)
        do {_=try await store.receiveReviewedTextRevisions(payload,identity:identity);XCTFail("Revoked replay accepted")}catch{}
        let retained=try await store.list();XCTAssertEqual(retained.count,1)
        let other=try SQLiteConversationStore(url:path()),oldScope=try await scope(other)
        _=try await other.receiveReviewedTextRevisions(payload,identity:oldScope)
        try await other.deleteAll()
        do {_=try await other.receiveReviewedTextRevisions(payload,identity:oldScope);XCTFail("Erased scope replayed")}catch{}
        var next=base;next.title="After erase"
        do {_=try await other.receiveReviewedTextRevisions(envelope(next,base:base),identity:scope(other));XCTFail("Unknown erased ancestry accepted")}catch{}
    }
    func testMissingLineageMetadataFailsClosedButHistoryRemainsUsable() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),base=Conversation(title:"Local")
        try await store.save(base)
        try sql(url,"DROP TABLE text_revision_lineage")
        let reopened=try SQLiteConversationStore(url:url)
        do {_=try await reopened.receiveReviewedTextRevisions(envelope(base),identity:scope(reopened));XCTFail("Lost lineage was recreated")}catch{}
        let all=try await reopened.list();XCTAssertEqual(all.map(\.title),["Local"])
        try await reopened.deleteAll()
    }
    func testKnownRevocationSchemaMigratesWithoutRevivingPeer() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url)
        try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation)
        try sql(url,"DROP TABLE text_revision_lineage; PRAGMA user_version=1")
        let migrated=try SQLiteConversationStore(url:url)
        let revoked=try await migrated.isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:generation)
        XCTAssertTrue(revoked)
        do {_=try await migrated.receiveReviewedTextRevisions(envelope(Conversation(title:"Denied")),identity:scope(migrated));XCTFail("Migration revived peer")}catch{}
    }
    func testCapacityFailureCannotLeaveNewContentOrReceipt() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),base=Conversation(title:"Over capacity")
        try sql(url,"WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<10000) INSERT INTO text_revision_lineage(peer,generation,source,local_id,remote_base,local_base) SELECT zeroblob(32),'00000000-0000-0000-0000-000000000001',printf('00000000-0000-0000-0000-%012X',x),printf('00000000-0000-0000-0000-%012X',x),x'7B7D',x'7B7D' FROM n")
        let identity=try await scope(store),payload=try envelope(base)
        do {_=try await store.receiveReviewedTextRevisions(payload,identity:identity);XCTFail("Capacity silently exceeded")}catch{}
        let all=try await store.list();XCTAssertTrue(all.isEmpty)
        try sql(url,"DELETE FROM text_revision_lineage")
        let retry=try await store.receiveReviewedTextRevisions(payload,identity:identity)
        XCTAssertEqual(retry.records[0].disposition,.inserted)
    }
}
