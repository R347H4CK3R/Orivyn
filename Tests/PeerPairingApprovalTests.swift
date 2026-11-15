import XCTest
@testable import PairingPolicy

final class PeerPairingApprovalTests: XCTestCase {
    let local = Data(repeating: 1, count: 32)
    let remote = Data(repeating: 2, count: 32)
    func offer(generation: UUID = UUID()) -> PeerPairingOffer {
        PeerPairingOffer(version: 1, pairingGeneration: generation, certificateDER: Data([1,2,3]))
    }
    @MainActor func coordinator() -> PeerPairingCoordinator {
        PeerPairingCoordinator(localCertificateSHA256: local, certificateSHA256: { _ in self.remote })
    }
    @MainActor func testOfferDoesNotGrantAuthority() throws {
        let c = coordinator()
        try c.review(offer())
        XCTAssertNil(c.approved)
    }
    @MainActor func testWrongFingerprintFailsClosed() throws {
        let c = coordinator(); try c.review(offer())
        XCTAssertThrowsError(try c.approve(independentlyVerifiedFingerprint: String(repeating:"00",count:32),
            sourceIDs: [UUID()], receiverEpoch: UUID()))
        XCTAssertNil(c.approved)
    }
    @MainActor func testEmptyScopeFails() throws {
        let c = coordinator(); try c.review(offer())
        XCTAssertThrowsError(try c.approve(independentlyVerifiedFingerprint: String(repeating:"02",count:32),
            sourceIDs: [], receiverEpoch: UUID()))
    }
    @MainActor func testApprovalBindsExactIdentityScopeAndEpoch() throws {
        let c = coordinator(); let o = offer(); let source = UUID(), epoch = UUID()
        try c.review(o)
        let a = try c.approve(independentlyVerifiedFingerprint: String(repeating:"02",count:32), sourceIDs:[source], receiverEpoch:epoch)
        XCTAssertEqual(a.peerCertificateSHA256,remote); XCTAssertEqual(a.localCertificateSHA256,local)
        XCTAssertEqual(a.pairingGeneration,o.pairingGeneration); XCTAssertEqual(a.receiverEpoch,epoch)
        XCTAssertEqual(a.approvedSourceIDs,[source]); XCTAssertEqual(c.approved,a)
    }
    @MainActor func testRevokeRejectsReplayedGeneration() throws {
        let c = coordinator(); let o = offer(); try c.review(o)
        _ = try c.approve(independentlyVerifiedFingerprint:String(repeating:"02",count:32),sourceIDs:[UUID()],receiverEpoch:UUID())
        c.revoke()
        XCTAssertNil(c.approved); XCTAssertThrowsError(try c.review(o))
    }
    @MainActor func testIdentityChangeDropsPendingAndApproved() throws {
        let c = coordinator(); try c.review(offer())
        c.replaceLocalIdentity(certificateSHA256:Data(repeating:3,count:32))
        XCTAssertNil(c.pending); XCTAssertNil(c.approved)
        XCTAssertThrowsError(try c.approve(independentlyVerifiedFingerprint:String(repeating:"02",count:32),sourceIDs:[UUID()],receiverEpoch:UUID()))
    }
    @MainActor func testNewOfferRequiresRevocationFirst() throws {
        let c = coordinator(); try c.review(offer())
        _ = try c.approve(independentlyVerifiedFingerprint:String(repeating:"02",count:32),sourceIDs:[UUID()],receiverEpoch:UUID())
        XCTAssertThrowsError(try c.review(offer()))
        XCTAssertNotNil(c.approved)
    }
    @MainActor func testSelfPairingRejected() throws {
        let c = PeerPairingCoordinator(localCertificateSHA256:local,certificateSHA256:{ _ in self.local })
        XCTAssertThrowsError(try c.review(offer()))
    }
    func testDecoderBoundsAndVersion() throws {
        XCTAssertThrowsError(try PeerPairingOffer.decode(Data(repeating:32,count:24001)))
        let unsupported = PeerPairingOffer(version:2,pairingGeneration:UUID(),certificateDER:Data([1]))
        XCTAssertThrowsError(try PeerPairingOffer.decode(JSONEncoder().encode(unsupported)))
        let empty = PeerPairingOffer(version:1,pairingGeneration:UUID(),certificateDER:Data())
        XCTAssertThrowsError(try PeerPairingOffer.decode(JSONEncoder().encode(empty)))
        let valid = offer()
        XCTAssertEqual(try PeerPairingOffer.decode(JSONEncoder().encode(valid)),valid)
    }
}
