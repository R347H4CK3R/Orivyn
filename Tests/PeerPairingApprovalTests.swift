import XCTest
#if canImport(PairingPolicy)
@testable import PairingPolicy
#else
@testable import JarvisEVO
#endif

final class PeerPairingApprovalTests: XCTestCase {
    let local = Data(repeating: 1, count: 32)
    let remote = Data(repeating: 2, count: 32)
    func offer(generation: UUID = UUID()) -> PeerPairingOffer {
        PeerPairingOffer(version: 1, pairingGeneration: generation, certificateDER: Data([1,2,3]))
    }
    @MainActor func coordinator() -> PeerPairingCoordinator {
        PeerPairingCoordinator(localCertificateSHA256: local, certificateSHA256: { _ in self.remote })
    }
    @MainActor func testOfferDoesNotGrantAuthority() async throws {
        let c = coordinator()
        try c.review(offer())
        XCTAssertNil(c.approved)
    }
    @MainActor func testWrongFingerprintFailsClosed() async throws {
        let c = coordinator(); try c.review(offer())
        XCTAssertThrowsError(try c.approve(independentlyVerifiedFingerprint: String(repeating:"00",count:32),
            sourceIDs: [UUID()], receiverEpoch: UUID()))
        XCTAssertNil(c.approved)
    }
    @MainActor func testEmptyScopeFails() async throws {
        let c = coordinator(); try c.review(offer())
        XCTAssertThrowsError(try c.approve(independentlyVerifiedFingerprint: String(repeating:"02",count:32),
            sourceIDs: [], receiverEpoch: UUID()))
    }
    @MainActor func testApprovalBindsExactIdentityScopeAndEpoch() async throws {
        let c = coordinator(); let o = offer(); let source = UUID(), epoch = UUID()
        try c.review(o)
        let a = try c.approve(independentlyVerifiedFingerprint: String(repeating:"02",count:32), sourceIDs:[source], receiverEpoch:epoch)
        XCTAssertEqual(a.peerCertificateSHA256,remote); XCTAssertEqual(a.localCertificateSHA256,local)
        XCTAssertEqual(a.pairingGeneration,o.pairingGeneration); XCTAssertEqual(a.receiverEpoch,epoch)
        XCTAssertEqual(a.approvedSourceIDs,[source]); XCTAssertEqual(c.approved,a)
    }
    @MainActor func testRevokeRejectsReplayedGeneration() async throws {
        let c = coordinator(); let o = offer(); try c.review(o)
        _ = try c.approve(independentlyVerifiedFingerprint:String(repeating:"02",count:32),sourceIDs:[UUID()],receiverEpoch:UUID())
        c.revoke()
        XCTAssertNil(c.approved); XCTAssertThrowsError(try c.review(o))
    }
    @MainActor func testIdentityChangeDropsPendingAndApproved() async throws {
        let c = coordinator(); try c.review(offer())
        c.replaceLocalIdentity(certificateSHA256:Data(repeating:3,count:32))
        XCTAssertNil(c.pending); XCTAssertNil(c.approved)
        XCTAssertThrowsError(try c.approve(independentlyVerifiedFingerprint:String(repeating:"02",count:32),sourceIDs:[UUID()],receiverEpoch:UUID()))
    }
    @MainActor func testNewOfferRequiresRevocationFirst() async throws {
        let c = coordinator(); try c.review(offer())
        _ = try c.approve(independentlyVerifiedFingerprint:String(repeating:"02",count:32),sourceIDs:[UUID()],receiverEpoch:UUID())
        XCTAssertThrowsError(try c.review(offer()))
        XCTAssertNotNil(c.approved)
    }
    @MainActor func testSelfPairingRejected() async throws {
        let c = PeerPairingCoordinator(localCertificateSHA256:local,certificateSHA256:{ _ in self.local })
        XCTAssertThrowsError(try c.review(offer()))
    }
    func testUntrustedMetadataIsBoundedAndOptional() throws {
        let id = UUID(), generation = UUID(), epoch = UUID()
        let record = PeerPairingOffer.Conversation(id: id, title: "Reviewed notes")
        let valid = PeerPairingOffer(version: 1, pairingGeneration: generation, certificateDER: Data([1]),
            receiverEpoch: epoch, offeredConversations: [record])
        XCTAssertEqual(try PeerPairingOffer.decode(JSONEncoder().encode(valid)), valid)
        let duplicate = PeerPairingOffer(version: 1, pairingGeneration: generation, certificateDER: Data([1]),
            offeredConversations: [record, record])
        XCTAssertThrowsError(try duplicate.validate())
        let controlTitle = PeerPairingOffer(version: 1, pairingGeneration: generation, certificateDER: Data([1]),
            offeredConversations: [.init(id: id, title: "hidden\nname")])
        XCTAssertThrowsError(try controlTitle.validate())
        let hugeTitle = PeerPairingOffer(version: 1, pairingGeneration: generation, certificateDER: Data([1]),
            offeredConversations: [.init(id: id, title: String(repeating: "x", count: 241))])
        XCTAssertThrowsError(try hugeTitle.validate())
        let legacy: [String: Any] = ["version": 1, "pairingGeneration": generation.uuidString,
            "certificateDER": Data([1]).base64EncodedString()]
        let decoded = try PeerPairingOffer.decode(JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.receiverEpoch); XCTAssertTrue(decoded.offeredConversations.isEmpty)
    }
    func testDecoderBoundsAndVersion() throws {
        XCTAssertThrowsError(try PeerPairingOffer.decode(Data(repeating:32,count:64001)))
        let unsupported = PeerPairingOffer(version:2,pairingGeneration:UUID(),certificateDER:Data([1]))
        XCTAssertThrowsError(try PeerPairingOffer.decode(JSONEncoder().encode(unsupported)))
        let empty = PeerPairingOffer(version:1,pairingGeneration:UUID(),certificateDER:Data())
        XCTAssertThrowsError(try PeerPairingOffer.decode(JSONEncoder().encode(empty)))
        let valid = offer()
        XCTAssertEqual(try PeerPairingOffer.decode(JSONEncoder().encode(valid)),valid)
    }
}
