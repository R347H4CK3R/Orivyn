import XCTest
import SQLite3
@testable import JarvisEVO

final class TextRevisionSenderTests: XCTestCase {
    private let sender=Data(repeating:3,count:32),peer=Data(repeating:8,count:32),generation=UUID()
    private func path()->URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite") }
    private func stage(_ store:SQLiteConversationStore,_ value:Conversation,epoch:UUID) async throws -> StagedTextSend {
        try await store.stageTextRevisionSend(ReviewedTextSnapshot(conversations:[value]),senderCertificateSHA256:sender,peerCertificateSHA256:peer,pairingGeneration:generation,receiverEpoch:epoch)
    }
    private func acknowledge(_ store:SQLiteConversationStore,_ draft:StagedTextSend) async throws {
        let envelope=try TextRevisionEnvelope.decodeCanonical(draft.payload)
        let summary=TextRevisionReceiveSummary(records:envelope.records.map{.init(sourceID:$0.incoming.id,localID:$0.incoming.id,disposition:$0.base == nil ? .inserted : .advanced,preservedLocalID:nil)})
        try await store.recordTextRevisionDeliveryReceipt(identity:draft.identity,payload:draft.payload,summary:summary)
    }
    private func sql(_ path:URL,_ query:String) throws { var db:OpaquePointer?;XCTAssertEqual(sqlite3_open(path.path,&db),SQLITE_OK);defer{sqlite3_close(db)};XCTAssertEqual(sqlite3_exec(db,query,nil,nil,nil),SQLITE_OK) }
    func testTwoStoresAdvanceOnlyAfterExactReceiverReceiptAndReopen() async throws {
        let url=path(),outgoing=try SQLiteConversationStore(url:url),incoming=try SQLiteConversationStore(url:path())
        let epoch=try await incoming.textReceiveEpoch(),value=Conversation(title:"First")
        try await outgoing.save(value)
        let first=try await stage(outgoing,value,epoch:epoch)
        let summary=try await incoming.receiveReviewedTextRevisions(first.payload,identity:first.identity.receiveIdentity)
        try await outgoing.recordTextRevisionDeliveryReceipt(identity:first.identity,payload:first.payload,summary:summary)
        try await outgoing.recordTextRevisionDeliveryReceipt(identity:first.identity,payload:first.payload,summary:summary)
        let reopened=try SQLiteConversationStore(url:url)
        var next=value;next.title="Next";try await reopened.save(next)
        let second=try await stage(reopened,next,epoch:epoch)
        XCTAssertEqual(try TextRevisionEnvelope.decodeCanonical(second.payload).records[0].base,value)
        let advanced=try await incoming.receiveReviewedTextRevisions(second.payload,identity:second.identity.receiveIdentity)
        XCTAssertEqual(advanced.records[0].disposition,.advanced)
        let all=try await incoming.list();XCTAssertEqual(all.map(\.title),["Next"])
    }
    func testOnlyOnePendingTransferPerDestinationAndDiscardDoesNotAdvanceBase() async throws {
        let store=try SQLiteConversationStore(url:path()),value=Conversation(title:"Pending"),epoch=UUID()
        try await store.save(value)
        let first=try await stage(store,value,epoch:epoch)
        do {_=try await stage(store,value,epoch:epoch);XCTFail("Overlapping transfer accepted")}catch{}
        let pending=try await store.pendingTextRevisionSendIDs();XCTAssertEqual(pending,[first.identity.transfer])
        try await store.discardTextRevisionSend(id:first.identity.transfer)
        let next=try await stage(store,value,epoch:epoch)
        XCTAssertNil(try TextRevisionEnvelope.decodeCanonical(next.payload).records[0].base)
    }
    func testLocalEditAfterStagingCannotChangeRetryBytesOrAcknowledgedBase() async throws {
        let store=try SQLiteConversationStore(url:path()),value=Conversation(title:"Reviewed"),epoch=UUID()
        try await store.save(value);let first=try await stage(store,value,epoch:epoch)
        var local=value;local.title="New edit";try await store.save(local)
        let retry=try await store.textRevisionSend(id:first.identity.transfer)
        XCTAssertEqual(retry?.payload,first.payload);XCTAssertEqual(retry?.delivered,false)
        try await acknowledge(store,first)
        let next=try await stage(store,local,epoch:epoch)
        let record=try TextRevisionEnvelope.decodeCanonical(next.payload).records[0]
        XCTAssertEqual(record.base,value);XCTAssertEqual(record.incoming,local)
    }
    func testChangedReceiptScopePayloadOrSummaryCannotAdvanceDraft() async throws {
        let store=try SQLiteConversationStore(url:path()),value=Conversation(title:"Exact"),epoch=UUID()
        try await store.save(value);let first=try await stage(store,value,epoch:epoch)
        let valid=TextRevisionReceiveSummary(records:[.init(sourceID:value.id,localID:value.id,disposition:.inserted,preservedLocalID:nil)])
        let wrong=TextSendIdentity(receiverEpoch:UUID(),transfer:first.identity.transfer,senderCertificateSHA256:sender,receiverCertificateSHA256:peer,pairingGeneration:generation)
        for payload in [Data(),first.payload+Data([32])] {
            do {try await store.recordTextRevisionDeliveryReceipt(identity:first.identity,payload:payload,summary:valid);XCTFail("Changed payload accepted")}catch{}
        }
        do {try await store.recordTextRevisionDeliveryReceipt(identity:wrong,payload:first.payload,summary:valid);XCTFail("Changed epoch accepted")}catch{}
        let mismatched=TextRevisionReceiveSummary(records:[.init(sourceID:UUID(),localID:value.id,disposition:.inserted,preservedLocalID:nil)])
        do {try await store.recordTextRevisionDeliveryReceipt(identity:first.identity,payload:first.payload,summary:mismatched);XCTFail("Wrong source accepted")}catch{}
        try await store.recordTextRevisionDeliveryReceipt(identity:first.identity,payload:first.payload,summary:valid)
        let changed=TextRevisionReceiveSummary(records:[.init(sourceID:value.id,localID:UUID(),disposition:.conflict,preservedLocalID:value.id)])
        do {try await store.recordTextRevisionDeliveryReceipt(identity:first.identity,payload:first.payload,summary:changed);XCTFail("Different replay accepted")}catch{}
    }
    func testStaleReviewAndSelfDestinationRejectWithoutStaging() async throws {
        let store=try SQLiteConversationStore(url:path()),value=Conversation(title:"Old")
        var next=value;next.title="Changed";try await store.save(next)
        do {_=try await stage(store,value,epoch:UUID());XCTFail("Stale review staged")}catch{}
        do {_=try await store.stageTextRevisionSend(ReviewedTextSnapshot(conversations:[next]),senderCertificateSHA256:peer,peerCertificateSHA256:peer,pairingGeneration:generation,receiverEpoch:UUID());XCTFail("Self destination accepted")}catch{}
        let pending=try await store.pendingTextRevisionSendIDs();XCTAssertTrue(pending.isEmpty)
    }
    func testRevocationClearsRevisionStateAndBlocksRetries() async throws {
        let store=try SQLiteConversationStore(url:path()),value=Conversation(title:"Revoked"),epoch=UUID()
        try await store.save(value);let first=try await stage(store,value,epoch:epoch)
        try await acknowledge(store,first)
        let next=try await stage(store,value,epoch:epoch)
        try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation)
        let missing=try await store.textRevisionSend(id:next.identity.transfer);XCTAssertNil(missing)
        do {try await acknowledge(store,next);XCTFail("Revoked receipt accepted")}catch{}
        do {_=try await stage(store,value,epoch:epoch);XCTFail("Revoked transfer staged")}catch{}
        let local=try await store.list();XCTAssertEqual(local.count,1)
    }
    func testErasureClearsOutgoingBytesAndAcknowledgedBases() async throws {
        let store=try SQLiteConversationStore(url:path()),value=Conversation(title:"Erase"),epoch=UUID()
        try await store.save(value);let first=try await stage(store,value,epoch:epoch)
        try await acknowledge(store,first);try await store.deleteAll()
        let missing=try await store.textRevisionSend(id:first.identity.transfer);XCTAssertNil(missing)
        do {try await acknowledge(store,first);XCTFail("Erased transfer acknowledged")}catch{}
        try await store.save(value);let fresh=try await stage(store,value,epoch:epoch)
        XCTAssertNil(try TextRevisionEnvelope.decodeCanonical(fresh.payload).records[0].base)
    }
    func testSenderPairingGenerationAndReceiverEpochDoNotShareBases() async throws {
        let store=try SQLiteConversationStore(url:path()),value=Conversation(title:"Scoped"),epoch=UUID()
        try await store.save(value);let first=try await stage(store,value,epoch:epoch);try await acknowledge(store,first)
        for (localPin,gen,remoteEpoch) in [(Data(repeating:4,count:32),generation,epoch),(sender,UUID(),epoch),(sender,generation,UUID())] {
            let fresh=try await store.stageTextRevisionSend(ReviewedTextSnapshot(conversations:[value]),senderCertificateSHA256:localPin,peerCertificateSHA256:peer,pairingGeneration:gen,receiverEpoch:remoteEpoch)
            XCTAssertNil(try TextRevisionEnvelope.decodeCanonical(fresh.payload).records[0].base)
            try await store.discardTextRevisionSend(id:fresh.identity.transfer)
        }
    }
    func testReceiptWriteFailureRollsBackBeforeRetry() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),value=Conversation(title:"Atomic"),epoch=UUID()
        try await store.save(value);let first=try await stage(store,value,epoch:epoch)
        try sql(url,"CREATE TRIGGER reject_sent BEFORE INSERT ON text_revision_sent BEGIN SELECT RAISE(ABORT,'fixture'); END")
        do {try await acknowledge(store,first);XCTFail("Partial receipt committed")}catch{}
        let pending=try await store.textRevisionSend(id:first.identity.transfer);XCTAssertEqual(pending?.delivered,false)
        try sql(url,"DROP TRIGGER reject_sent");try await acknowledge(store,first)
        let delivered=try await store.textRevisionSend(id:first.identity.transfer);XCTAssertEqual(delivered?.delivered,true)
    }
    func testLostSenderMetadataIsNotRecreatedButLocalHistoryWorks() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),value=Conversation(title:"Retained")
        try await store.save(value);try sql(url,"DROP TABLE text_revision_sent")
        let reopened=try SQLiteConversationStore(url:url)
        do {_=try await stage(reopened,value,epoch:UUID());XCTFail("Missing ancestry recreated")}catch{}
        let all=try await reopened.list();XCTAssertEqual(all.map(\.title),["Retained"])
        try await reopened.deleteAll()
    }
    func testRevisionSenderMigrationKeepsReceiverLineageAndRevocation() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),value=Conversation(title:"Received")
        let scope=ReviewedTextReceiveIdentity(epoch:try await store.textReceiveEpoch(),transfer:UUID(),peerCertificateSHA256:sender,pairingGeneration:generation)
        _=try await store.receiveReviewedTextRevisions(TextRevisionEnvelope(records:[.init(base:nil,incoming:value)]).data,identity:scope)
        try await store.revokeTextPeer(peerCertificateSHA256:peer,pairingGeneration:generation)
        try sql(url,"DROP TABLE text_revision_outbox; DROP TABLE text_revision_sent; PRAGMA user_version=2")
        let reopened=try SQLiteConversationStore(url:url)
        let revoked=try await reopened.isTextPeerRevoked(peerCertificateSHA256:peer,pairingGeneration:generation);XCTAssertTrue(revoked)
        var next=value;next.title="Next"
        let newScope=ReviewedTextReceiveIdentity(epoch:scope.epoch,transfer:UUID(),peerCertificateSHA256:sender,pairingGeneration:generation)
        let result=try await reopened.receiveReviewedTextRevisions(TextRevisionEnvelope(records:[.init(base:value,incoming:next)]).data,identity:newScope)
        XCTAssertEqual(result.records[0].disposition,.advanced)
    }
    func testReceiptCapacityFailureDoesNotMarkDelivery() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),value=Conversation(title:"Capacity"),epoch=UUID()
        try await store.save(value);let first=try await stage(store,value,epoch:epoch)
        try sql(url,"WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<10000) INSERT INTO text_revision_sent(sender,peer,generation,receiver_epoch,source,payload) SELECT zeroblob(32),zeroblob(32),'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',printf('00000000-0000-0000-0000-%012X',x),x'7B7D' FROM n")
        do {try await acknowledge(store,first);XCTFail("Capacity exceeded")}catch{}
        let pending=try await store.textRevisionSend(id:first.identity.transfer);XCTAssertEqual(pending?.delivered,false)
        try sql(url,"DELETE FROM text_revision_sent");try await acknowledge(store,first)
    }
    func testReceiverConflictReceiptStillAdvancesOnlyRemoteBranch() async throws {
        let outgoing=try SQLiteConversationStore(url:path()),incoming=try SQLiteConversationStore(url:path()),value=Conversation(title:"Original")
        let epoch=try await incoming.textReceiveEpoch()
        try await outgoing.save(value);try await incoming.save(value)
        let first=try await stage(outgoing,value,epoch:epoch)
        let conflict=try await incoming.receiveReviewedTextRevisions(first.payload,identity:first.identity.receiveIdentity)
        XCTAssertEqual(conflict.records[0].disposition,.conflict)
        try await outgoing.recordTextRevisionDeliveryReceipt(identity:first.identity,payload:first.payload,summary:conflict)
        var next=value;next.title="Remote next";try await outgoing.save(next)
        let second=try await stage(outgoing,next,epoch:epoch)
        let advanced=try await incoming.receiveReviewedTextRevisions(second.payload,identity:second.identity.receiveIdentity)
        XCTAssertEqual(advanced.records[0].localID,conflict.records[0].localID)
        let all=try await incoming.list();XCTAssertEqual(Set(all.map(\.title)),["Original","Remote next"])
    }
}

extension TextRevisionSenderTests {
    private static func tryStage(_ store:SQLiteConversationStore,snapshot:ReviewedTextSnapshot,sender:Data,peer:Data,generation:UUID,epoch:UUID) async -> Bool {
        do {_=try await store.stageTextRevisionSend(snapshot,senderCertificateSHA256:sender,peerCertificateSHA256:peer,pairingGeneration:generation,receiverEpoch:epoch);return true}catch{return false}
    }
    func testTwoConnectionsCannotStageOverlappingTransfers() async throws {
        let url=path(),first=try SQLiteConversationStore(url:url),second=try SQLiteConversationStore(url:url),value=Conversation(title:"Concurrent"),epoch=UUID()
        try await first.save(value)
        let snapshot=try ReviewedTextSnapshot(conversations:[value])
        let localSender=sender,localPeer=peer,localGeneration=generation
        async let a=Self.tryStage(first,snapshot:snapshot,sender:localSender,peer:localPeer,generation:localGeneration,epoch:epoch)
        async let b=Self.tryStage(second,snapshot:snapshot,sender:localSender,peer:localPeer,generation:localGeneration,epoch:epoch)
        let outcomes=await [a,b];XCTAssertEqual(outcomes.filter{$0}.count,1)
        let pending=try await first.pendingTextRevisionSendIDs();XCTAssertEqual(pending.count,1)
    }
    func testLateReceiptReplayCannotRewindAcknowledgedBase() async throws {
        let store=try SQLiteConversationStore(url:path()),value=Conversation(title:"First"),epoch=UUID()
        try await store.save(value);let first=try await stage(store,value,epoch:epoch);try await acknowledge(store,first)
        var next=value;next.title="Next";try await store.save(next)
        let second=try await stage(store,next,epoch:epoch);try await acknowledge(store,second)
        try await acknowledge(store,first)
        var latest=next;latest.title="Latest";try await store.save(latest)
        let third=try await stage(store,latest,epoch:epoch)
        XCTAssertEqual(try TextRevisionEnvelope.decodeCanonical(third.payload).records[0].base,next)
    }
    func testMissingSerializationIndexPausesSenderWithoutBlockingHistory() async throws {
        let url=path(),store=try SQLiteConversationStore(url:url),value=Conversation(title:"Local")
        try await store.save(value);try sql(url,"DROP INDEX text_revision_one_pending")
        let reopened=try SQLiteConversationStore(url:url)
        do {_=try await stage(reopened,value,epoch:UUID());XCTFail("Missing serialization metadata was ignored")}catch{}
        let all=try await reopened.list();XCTAssertEqual(all.map(\.title),["Local"])
        try await reopened.deleteAll()
    }
    func testNoOpReceiptPreservesExactBase() async throws {
        let outgoing=try SQLiteConversationStore(url:path()),incoming=try SQLiteConversationStore(url:path()),value=Conversation(title:"Same")
        let epoch=try await incoming.textReceiveEpoch()
        try await outgoing.save(value);let first=try await stage(outgoing,value,epoch:epoch)
        let inserted=try await incoming.receiveReviewedTextRevisions(first.payload,identity:first.identity.receiveIdentity)
        try await outgoing.recordTextRevisionDeliveryReceipt(identity:first.identity,payload:first.payload,summary:inserted)
        let second=try await stage(outgoing,value,epoch:epoch)
        let same=try await incoming.receiveReviewedTextRevisions(second.payload,identity:second.identity.receiveIdentity)
        XCTAssertEqual(same.records[0].disposition,.unchanged)
        try await outgoing.recordTextRevisionDeliveryReceipt(identity:second.identity,payload:second.payload,summary:same)
        let delivered=try await outgoing.textRevisionSend(id:second.identity.transfer);XCTAssertEqual(delivered?.delivered,true)
    }
}
