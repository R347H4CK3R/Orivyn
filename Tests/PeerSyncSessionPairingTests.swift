#if ORIVYN_PEER_TLS_SPIKE && canImport(Network) && canImport(Security) && canImport(CryptoKit) && canImport(X509) && os(iOS)
import XCTest
import CryptoKit
@testable import JarvisEVO

/// Real Keychain identities, offer encoding, session methods and SQLite gates.
/// No connection/listener is started. Lifecycle availability is supplied to the
/// actual session API; these are not physical lock or two-device network tests.
@MainActor
final class PeerSyncSessionPairingTests: XCTestCase {
    private var root: URL!
    private var senderStore: SQLiteConversationStore!
    private var receiverStore: SQLiteConversationStore!
    private var senderProvisioner: PeerIdentityProvisioner!
    private var receiverProvisioner: PeerIdentityProvisioner!
    private var sender: PeerSyncSession!
    private var receiver: PeerSyncSession!
    private var conversation: Conversation!
    private var senderDocument = ""

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        senderStore = try SQLiteConversationStore(url: root.appendingPathComponent("sender.sqlite"))
        receiverStore = try SQLiteConversationStore(url: root.appendingPathComponent("receiver.sqlite"))
        let testNamespace = "app.jarvisevo.tests.peer-session.\(UUID().uuidString)"
        senderProvisioner = PeerIdentityProvisioner(namespace: testNamespace + ".sender")
        receiverProvisioner = PeerIdentityProvisioner(namespace: testNamespace + ".receiver")
        sender = makeSession(store: senderStore, provisioner: senderProvisioner)
        receiver = makeSession(store: receiverStore, provisioner: receiverProvisioner)
        activate(sender); activate(receiver)
        conversation = Conversation(title: "Explicitly selected text",
            messages: [ChatMessage(role: .user, content: "Only this conversation is proposed")])
        try await senderStore.save(conversation)
        try await sender.prepareOffer(conversations: [conversation], sourceIDs: [conversation.id])
        senderDocument = sender.localOfferText
        try await receiver.prepareOffer(conversations: [], sourceIDs: [])
        try receiver.review(text: senderDocument, direction: .receive, host: "", port: "49152")
        // Actual responder flow: regenerate the public reply while review stays
        // pending, using the initiator's generation instead of a second random one.
        try await receiver.prepareOffer(conversations: [], sourceIDs: [])
        try sender.review(text: receiver.localOfferText, direction: .send, host: "127.0.0.1", port: "49152")
    }

    override func tearDown() async throws {
        // Session revocation precedes deletion of namespaced test identities.
        if let sender { await sender.revoke() }
        if let receiver { await receiver.revoke() }
        if let senderProvisioner { try await senderProvisioner.deleteAfterRevocation() }
        if let receiverProvisioner { try await receiverProvisioner.deleteAfterRevocation() }
        sender = nil; receiver = nil
        senderStore = nil; receiverStore = nil
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func activate(_ session: PeerSyncSession) {
        session.setForeground(true)
        session.setProtectedDataAvailable(true)
    }

    private func makeSession(store: SQLiteConversationStore,
                             provisioner: PeerIdentityProvisioner) -> PeerSyncSession {
        PeerSyncSession(store: store, provisioner: provisioner,
            snapshot: { ids in try await store.exportTextSnapshot(ids: ids) },
            receive: { _, channel in
                channel.cancel()
                XCTFail("Pairing-state tests must not start a transfer")
            })
    }

    private func approveBoth() async throws {
        try await receiver.approve(fingerprint: sender.localFingerprint, sourceIDs: [conversation.id])
        try await sender.approve(fingerprint: receiver.localFingerprint, sourceIDs: [conversation.id])
    }

    func testRealIdentityRoundTripApprovesExactDirectionButDoesNotEnable() async throws {
        let firstOffer = try PeerPairingOffer.decode(Data(senderDocument.utf8))
        let reply = try PeerPairingOffer.decode(Data(receiver.localOfferText.utf8))
        XCTAssertEqual(firstOffer.pairingGeneration, reply.pairingGeneration)
        XCTAssertNotEqual(firstOffer.certificateDER, reply.certificateDER)
        XCTAssertEqual(firstOffer.offeredConversations.map(\.id), [conversation.id])
        XCTAssertTrue(reply.offeredConversations.isEmpty)
        try await approveBoth()
        let sendApproval = try XCTUnwrap(sender.approval)
        let receiveApproval = try XCTUnwrap(receiver.approval)
        let receiverEpoch = try await receiverStore.textReceiveEpoch()
        XCTAssertEqual(sendApproval.pairingGeneration, firstOffer.pairingGeneration)
        XCTAssertEqual(receiveApproval.pairingGeneration, sendApproval.pairingGeneration)
        XCTAssertEqual(sendApproval.receiverEpoch, receiverEpoch)
        XCTAssertEqual(receiveApproval.receiverEpoch, receiverEpoch)
        XCTAssertEqual(sendApproval.approvedSourceIDs, [conversation.id])
        XCTAssertEqual(receiveApproval.approvedSourceIDs, [conversation.id])
        XCTAssertEqual(sendApproval.localCertificateSHA256, Data(SHA256.hash(data: firstOffer.certificateDER)))
        XCTAssertEqual(sendApproval.peerCertificateSHA256, receiveApproval.localCertificateSHA256)
        XCTAssertEqual(receiveApproval.peerCertificateSHA256, sendApproval.localCertificateSHA256)
        XCTAssertEqual(sender.direction, .send)
        XCTAssertEqual(receiver.direction, .receive)
        XCTAssertFalse(sender.enabled); XCTAssertFalse(receiver.enabled)
        XCTAssertEqual(sender.status, "Off"); XCTAssertEqual(receiver.status, "Off")
        XCTAssertNil(sender.listeningPort); XCTAssertNil(receiver.listeningPort)
    }

    func testWrongFingerprintCannotApproveRealOfferAndCorrectRetryCan() async throws {
        let correct = receiver.localFingerprint
        let wrong = (correct.first == "0" ? "1" : "0") + String(correct.dropFirst())
        do {
            try await sender.approve(fingerprint: wrong, sourceIDs: [conversation.id])
            XCTFail("Wrong fingerprint must never grant consent")
        } catch PeerPairingCoordinator.Failure.fingerprintMismatch {} catch { XCTFail("Unexpected: \(error)") }
        XCTAssertNil(sender.approval)
        XCTAssertNotNil(sender.pendingOffer)
        XCTAssertFalse(sender.enabled)
        try await sender.approve(fingerprint: correct, sourceIDs: [conversation.id])
        XCTAssertNotNil(sender.approval)
        XCTAssertFalse(sender.enabled)
    }

    func testBackgroundCancelsRealPendingReviewAndCannotResumeApproval() async throws {
        XCTAssertNotNil(sender.pendingOffer)
        sender.setForeground(false)
        XCTAssertNil(sender.pendingOffer)
        activate(sender)
        do {
            try await sender.approve(fingerprint: receiver.localFingerprint, sourceIDs: [conversation.id])
            XCTFail("A canceled review cannot become authority after activation")
        } catch PeerSyncSession.Failure.unavailable {} catch { XCTFail("Unexpected: \(error)") }
        XCTAssertNil(sender.approval)
        XCTAssertFalse(sender.enabled)
        XCTAssertEqual(sender.status, "Off")
    }

    func testRevocationPersistsAndFreshSessionRejectsOldRealPairing() async throws {
        try await approveBoth()
        let previous = try XCTUnwrap(receiver.approval)
        await receiver.revoke()
        XCTAssertNil(receiver.approval)
        XCTAssertFalse(receiver.enabled)
        XCTAssertNil(receiver.failure)
        let revoked = try await receiverStore.isTextPeerRevoked(
            peerCertificateSHA256: previous.peerCertificateSHA256,
            pairingGeneration: previous.pairingGeneration)
        XCTAssertTrue(revoked)
        // A new coordinator has no in-memory retired generations. It must still
        // reject the old approved binding via the actual durable SQLite gate.
        receiver = makeSession(store: receiverStore, provisioner: receiverProvisioner)
        activate(receiver)
        try await receiver.prepareOffer(conversations: [], sourceIDs: [])
        try receiver.review(text: senderDocument, direction: .receive, host: "", port: "49152")
        do {
            try await receiver.approve(fingerprint: sender.localFingerprint, sourceIDs: [conversation.id])
            XCTFail("Restart must not bypass durable revocation")
        } catch PeerSyncSession.Failure.revoked {} catch { XCTFail("Unexpected: \(error)") }
        XCTAssertNil(receiver.approval)
        XCTAssertFalse(receiver.enabled)
        XCTAssertNil(receiver.listeningPort)
    }
}
#endif
