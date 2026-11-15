#if ORIVYN_PEER_TLS_SPIKE && canImport(Network) && canImport(Security) && canImport(CryptoKit) && canImport(X509) && os(iOS)
import XCTest
@testable import JarvisEVO

@MainActor
final class PeerSyncSessionPolicyTests: XCTestCase {
    private var root: URL!
    private var session: PeerSyncSession!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        session = PeerSyncSession(store: store, snapshot: { _ in
            XCTFail("Unapproved policy checks must not read conversation snapshots")
            throw CancellationError()
        }, receive: { _, channel in
            channel.cancel()
            XCTFail("Unapproved policy checks must not accept incoming history")
        })
    }
    override func tearDown() async throws {
        session.setEnabled(false)
        session = nil
        try? FileManager.default.removeItem(at: root)
    }

    func testNewSessionHasNoAuthorityAndEnableCannotGrantIt() {
        XCTAssertNil(session.approval)
        XCTAssertNil(session.pendingOffer)
        XCTAssertFalse(session.enabled)
        XCTAssertTrue(session.localFingerprint.isEmpty)
        XCTAssertTrue(session.localOfferText.isEmpty)
        session.setEnabled(true)
        session.retry()
        XCTAssertFalse(session.enabled)
        XCTAssertEqual(session.status, "Off")
        XCTAssertNil(session.listeningPort)
    }

    func testInactiveOfferPreparationRejectsBeforeProvisioning() async throws {
        // setForeground(false) reads actual protected-data availability, but the
        // foreground gate must still reject before touching Keychain identity.
        session.setForeground(false)
        do {
            try await session.prepareOffer(conversations: [], sourceIDs: [])
            XCTFail("Inactive setup must not provision an identity")
        } catch PeerSyncSession.Failure.unavailable {} catch { XCTFail("Unexpected: \(error)") }
        XCTAssertTrue(session.localFingerprint.isEmpty)
        XCTAssertTrue(session.localOfferText.isEmpty)
        XCTAssertNil(session.localEpoch)
        XCTAssertFalse(session.preparing)
    }

    func testLockedOfferPreparationRejectsBeforeProvisioning() async throws {
        session.setForeground(true)
        session.setProtectedDataAvailable(false)
        do {
            try await session.prepareOffer(conversations: [], sourceIDs: [])
            XCTFail("Locked setup must not provision an identity")
        } catch PeerSyncSession.Failure.unavailable {} catch { XCTFail("Unexpected: \(error)") }
        XCTAssertTrue(session.localFingerprint.isEmpty)
        XCTAssertNil(session.approval)
        XCTAssertNil(session.localEpoch)
        XCTAssertFalse(session.preparing)
    }

    func testPastedOfferAndLifecycleChangesCannotGrantTrust() async throws {
        session.setForeground(true)
        session.setProtectedDataAvailable(true)
        // Even a structurally valid public offer does not create local identity
        // or approval. The parser is downstream of the explicit setup gate.
        let offer = PeerPairingOffer(version: 1, pairingGeneration: UUID(),
            certificateDER: Data([1, 2, 3]), receiverEpoch: UUID())
        let text = String(decoding: try JSONEncoder().encode(offer), as: UTF8.self)
        do {
            try session.review(text: text, direction: .send, host: "127.0.0.1", port: "49152")
            XCTFail("Import without explicit identity setup must fail")
        } catch PeerSyncSession.Failure.unavailable {} catch { XCTFail("Unexpected: \(error)") }
        do {
            try await session.approve(fingerprint: String(repeating: "a", count: 64), sourceIDs: [UUID()])
            XCTFail("Approval without a pending review must fail")
        } catch PeerSyncSession.Failure.unavailable {} catch { XCTFail("Unexpected: \(error)") }
        session.setEnabled(true)
        session.setForeground(false)
        session.setForeground(true)
        session.setProtectedDataAvailable(true)
        session.retry()
        XCTAssertNil(session.pendingOffer)
        XCTAssertNil(session.approval)
        XCTAssertFalse(session.enabled)
        XCTAssertEqual(session.status, "Off")
        XCTAssertNil(session.listeningPort)
    }
}
#endif
