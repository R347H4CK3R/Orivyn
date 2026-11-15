#if ORIVYN_PEER_TLS_SPIKE && canImport(Network) && canImport(Security) && canImport(CryptoKit) && canImport(X509) && os(iOS)
import XCTest
import Network
@testable import JarvisEVO

/// Actual session, AppModel, Keychain, SQLite and authenticated loopback transport.
/// Lifecycle availability is injected through the real API. This does not prove
/// physical locking, LAN discovery, background execution or two-device behavior.
@MainActor
final class PeerSyncSessionEndToEndTests: XCTestCase {
    private var root: URL!
    private var suites: [String] = []
    private var sender: PeerSyncSession?
    private var receiver: PeerSyncSession?
    private var senderProvisioner: PeerIdentityProvisioner?
    private var receiverProvisioner: PeerIdentityProvisioner?
    private var historyOwner: Task<Void, Error>?
    private var releaseHistory: CheckedContinuation<Void, Never>?

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("peer-e2e-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        releaseHistory?.resume(); releaseHistory = nil
        if let historyOwner { _ = try? await historyOwner.value }
        if let sender { await sender.revoke() }
        if let receiver { await receiver.revoke() }
        if let senderProvisioner { try await senderProvisioner.deleteAfterRevocation() }
        if let receiverProvisioner { try await receiverProvisioner.deleteAfterRevocation() }
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        sender = nil; receiver = nil; historyOwner = nil
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func model(_ name: String) async throws -> (AppModel, SQLiteConversationStore) {
        let directory = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try SQLiteConversationStore(url: directory.appendingPathComponent("history.sqlite"))
        let suite = "Orivyn.PeerSessionE2E." + UUID().uuidString
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(false, forKey: "orivyn.automaticModels")
        let model = AppModel(store: store,
            attachmentService: try AttachmentService(directory: directory.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: directory.appendingPathComponent("Models")), defaults: defaults)
        await model.bootstrap()
        return (model, store)
    }

    private func waitUntil(_ label: String, seconds: TimeInterval = 15,
                           _ predicate: @MainActor () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if try await predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out: " + label)
        throw TestFailure.timeout
    }

    private enum TestFailure: Error { case timeout, portUnavailable }
    private enum PortEvent: Sendable { case ready(NWEndpoint.Port), cancelled, failed }
    private func unusedPort() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        let events = AsyncStream<PortEvent>.makeStream()
        let deadline = Task {
            do { try await Task.sleep(nanoseconds: 5_000_000_000) }
            catch { return }
            events.continuation.yield(.failed)
        }
        defer { deadline.cancel(); listener.cancel(); events.continuation.finish() }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = listener.port { events.continuation.yield(.ready(port)) }
            case .cancelled: events.continuation.yield(.cancelled)
            case .failed: events.continuation.yield(.failed)
            default: break
            }
        }
        listener.start(queue: DispatchQueue(label: "Orivyn.SessionPortFixture"))
        var selected: UInt16?
        for await event in events.stream {
            switch event {
            case .ready(let port): selected = port.rawValue; listener.cancel()
            case .cancelled:
                guard let selected else { throw TestFailure.portUnavailable }
                return selected
            case .failed: throw TestFailure.portUnavailable
            }
        }
        throw TestFailure.portUnavailable
    }

    func testReviewedSessionsAutomaticallyDeferBusyDeliverEditsAndHonorRevocation() async throws {
        let (senderModel, senderStore) = try await model("sender")
        let (receiverModel, receiverStore) = try await model("receiver")
        var selected = Conversation(title: "Approved synthetic conversation",
            messages: [ChatMessage(role: .user, content: "Approved text only")])
        let privateConversation = Conversation(title: "Not approved",
            messages: [ChatMessage(role: .user, content: "Must remain on sender")])
        try await senderStore.save(selected)
        try await senderStore.save(privateConversation)
        await senderModel.bootstrap()
        senderModel.draft = "Unsent sender draft"
        receiverModel.draft = "Unsent receiver draft"

        let namespace = "app.jarvisevo.tests.peer-e2e." + UUID().uuidString
        let sp = PeerIdentityProvisioner(namespace: namespace + ".sender")
        let rp = PeerIdentityProvisioner(namespace: namespace + ".receiver")
        senderProvisioner = sp; receiverProvisioner = rp
        var busyResponses = 0
        let sending = PeerSyncSession(store: senderStore, provisioner: sp,
            snapshot: { try await senderModel.preparePeerTextSnapshot(ids: $0) },
            receive: { _, channel in channel.cancel(); XCTFail("Send-only session received history") })
        let receiving = PeerSyncSession(store: receiverStore, provisioner: rp,
            snapshot: { _ in XCTFail("Receive-only session exported history"); throw TestFailure.timeout },
            receive: { auth, channel in
                do {
                    try await receiverModel.receivePeerTextRevisions(approvedSourceIDs: auth.approvedSourceIDs,
                        expectedEpoch: auth.receiverEpoch, over: channel)
                } catch PeerTextRevisionExchange.Failure.peerBusy {
                    busyResponses += 1
                    throw PeerTextRevisionExchange.Failure.peerBusy
                }
            })
        sender = sending; receiver = receiving
        for session in [sending, receiving] {
            session.setForeground(true)
            session.setProtectedDataAvailable(true)
        }
        let port = try await unusedPort()
        try await sending.prepareOffer(conversations: senderModel.conversations, sourceIDs: [selected.id])
        let senderOffer = sending.localOfferText
        try await receiving.prepareOffer(conversations: [], sourceIDs: [])
        try receiving.review(text: senderOffer, direction: .receive, host: "", port: String(port))
        try await receiving.prepareOffer(conversations: [], sourceIDs: [])
        try sending.review(text: receiving.localOfferText, direction: .send,
                           host: "127.0.0.1", port: String(port))
        try await receiving.approve(fingerprint: sending.localFingerprint, sourceIDs: [selected.id])
        try await sending.approve(fingerprint: receiving.localFingerprint, sourceIDs: [selected.id])
        let approvedReceiver = try XCTUnwrap(receiving.approval)
        XCTAssertFalse(sending.enabled); XCTAssertFalse(receiving.enabled)
        XCTAssertNil(receiving.listeningPort)
        let beforeEnable = try await senderStore.pendingTextRevisionSendIDs()
        XCTAssertTrue(beforeEnable.isEmpty)

        // Hold the actual history owner, forcing the admission-only busy path.
        historyOwner = Task { @MainActor in
            try await receiverModel.performPeerHistoryReceive {
                await withCheckedContinuation { self.releaseHistory = $0 }
            }
        }
        try await waitUntil("history owner acquired") { self.releaseHistory != nil }
        receiving.setEnabled(true)
        try await waitUntil("reviewed listener started") { receiving.listeningPort == port }
        sending.setEnabled(true)
        try await waitUntil("authenticated busy response") { busyResponses > 0 }
        let initialPending = try await senderStore.pendingTextRevisionSendIDs()
        let pendingID = try XCTUnwrap(initialPending.first)
        let initialTransfer = try await senderStore.textRevisionSend(id: pendingID)
        let before = try XCTUnwrap(initialTransfer)
        XCTAssertFalse(before.delivered)
        XCTAssertTrue(receiverModel.conversations.isEmpty)
        releaseHistory?.resume(); releaseHistory = nil
        try await historyOwner?.value
        historyOwner = nil

        try await waitUntil("same pending transfer delivered after owner releases") {
            let pending = try await senderStore.pendingTextRevisionSendIDs()
            return receiverModel.conversations == [selected] && pending.isEmpty
        }
        let deliveredTransfer = try await senderStore.textRevisionSend(id: pendingID)
        let delivered = try XCTUnwrap(deliveredTransfer)
        XCTAssertTrue(delivered.delivered)
        XCTAssertEqual(delivered.payload, before.payload)
        XCTAssertEqual(delivered.identity, before.identity)
        XCTAssertEqual(senderModel.draft, "Unsent sender draft")
        XCTAssertEqual(receiverModel.draft, "Unsent receiver draft")

        // Real time, not an injected scheduler: cross one ordinary 30s listener
        // expiry with unchanged sender text before editing.
        try await Task.sleep(nanoseconds: 35_000_000_000)
        XCTAssertTrue(sending.enabled); XCTAssertTrue(receiving.enabled)
        selected.title = "Edited after a real idle listener renewal"
        try await senderStore.save(selected)
        await senderModel.bootstrap()
        try await waitUntil("periodic edit delivery without manual retry", seconds: 40) {
            let pending = try await senderStore.pendingTextRevisionSendIDs()
            return receiverModel.conversations == [selected] && pending.isEmpty
        }
        XCTAssertEqual(receiverModel.draft, "Unsent receiver draft")
        XCTAssertFalse(receiverModel.conversations.contains { $0.id == privateConversation.id })
        let savedBeforeRevocation = receiverModel.conversations

        await receiving.revoke()
        XCTAssertFalse(receiving.enabled)
        XCTAssertNil(receiving.approval)
        XCTAssertNil(receiving.failure)
        let revoked = try await receiverStore.isTextPeerRevoked(
            peerCertificateSHA256: approvedReceiver.peerCertificateSHA256,
            pairingGeneration: approvedReceiver.pairingGeneration)
        XCTAssertTrue(revoked)
        receiving.setEnabled(true)
        XCTAssertFalse(receiving.enabled)
        selected.title = "Late edit must not reach revoked receiver"
        try await senderStore.save(selected)
        await senderModel.bootstrap()
        try await waitUntil("late edit staged but not acknowledged", seconds: 40) {
            !(try await senderStore.pendingTextRevisionSendIDs()).isEmpty
        }
        // Ensure the staged attempt has time to reach the closed endpoint.
        try await Task.sleep(nanoseconds: 2_000_000_000)
        sending.setEnabled(false)
        let lateIDs = try await senderStore.pendingTextRevisionSendIDs()
        XCTAssertEqual(lateIDs.count, 1)
        let lateID = try XCTUnwrap(lateIDs.first)
        let lateTransfer = try await senderStore.textRevisionSend(id: lateID)
        let late = try XCTUnwrap(lateTransfer)
        XCTAssertFalse(late.delivered)
        let receivedAfterRevocation = try await receiverStore.list(includeArchived: true)
        XCTAssertEqual(receivedAfterRevocation, savedBeforeRevocation)
        XCTAssertEqual(receiverModel.draft, "Unsent receiver draft")
        let senderHistory = try await senderStore.list(includeArchived: true)
        XCTAssertEqual(Set(senderHistory.map(\.id)), [selected.id, privateConversation.id])
    }
}
#endif
