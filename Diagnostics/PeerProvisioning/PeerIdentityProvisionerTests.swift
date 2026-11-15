import XCTest
import Foundation
import Security
import CryptoKit
import X509
import Network
@testable import PairingPolicy

final class PeerIdentityProvisionerTests: XCTestCase, @unchecked Sendable {
    func testCreateReloadSignAndDelete() async throws {
        let namespace = "orivyn.ci.identity." + UUID().uuidString
        let provisioner = PeerIdentityProvisioner(namespace: namespace)
        let created = try await provisioner.loadOrCreate()
        let again = try await PeerIdentityProvisioner(namespace: namespace).loadOrCreate()
        XCTAssertEqual(created.certificateSHA256, again.certificateSHA256)
        XCTAssertEqual(created.fingerprint.count, 64)
        let certificate = try Certificate(derEncoded: Array(created.certificateDER))
        XCTAssertTrue(certificate.publicKey.isValidSignature(certificate.signature, for: certificate))
        XCTAssertEqual(try certificate.extensions.basicConstraints, .notCertificateAuthority)
        XCTAssertTrue(try XCTUnwrap(certificate.extensions.extendedKeyUsage).contains(.clientAuth))
        XCTAssertTrue(try XCTUnwrap(certificate.extensions.extendedKeyUsage).contains(.serverAuth))
        var key: SecKey?
        XCTAssertEqual(SecIdentityCopyPrivateKey(created.identity, &key), errSecSuccess)
        let message = Data("proof-of-possession".utf8)
        var error: Unmanaged<CFError>?
        let signature = try XCTUnwrap(SecKeyCreateSignature(XCTUnwrap(key), .ecdsaSignatureMessageX962SHA256, message as CFData, &error))
        let certificateRef = try XCTUnwrap(SecCertificateCreateWithData(nil, created.certificateDER as CFData))
        let publicKey = try XCTUnwrap(SecCertificateCopyKey(certificateRef))
        XCTAssertTrue(SecKeyVerifySignature(publicKey, .ecdsaSignatureMessageX962SHA256, message as CFData, signature, &error))
        try await provisioner.deleteAfterRevocation()
        let removed = try await provisioner.load()
        XCTAssertNil(removed)
        let replacement = try await provisioner.loadOrCreate()
        XCTAssertNotEqual(created.certificateSHA256, replacement.certificateSHA256)
        try await provisioner.deleteAfterRevocation()
    }
    func testGeneratedIdentitiesAuthenticateWithMutualTLS() async throws {
        let a = PeerIdentityProvisioner(namespace: "orivyn.ci.tls.a." + UUID().uuidString)
        let b = PeerIdentityProvisioner(namespace: "orivyn.ci.tls.b." + UUID().uuidString)
        let first = try await a.loadOrCreate(), second = try await b.loadOrCreate()
        let generation = UUID()
        let server = PeerTLSProbe(pair: try PeerTLSProbePair(identity: first.identity,
            scannedPeerSHA256: second.certificateSHA256, peerCertificateDER: second.certificateDER, generation: generation))
        let client = PeerTLSProbe(pair: try PeerTLSProbePair(identity: second.identity,
            scannedPeerSHA256: first.certificateSHA256, peerCertificateDER: first.certificateDER, generation: generation))
        let results = await withCheckedContinuation { continuation in
            let collector = PairingHandshakeCollector(continuation)
            server.listen(on: .any, ready: { port in
                client.connect(to: .hostPort(host: "127.0.0.1", port: port)) {
                    collector.record($0, expectedPin: first.certificateSHA256, generation: generation)
                }
            }, completion: {
                collector.record($0, expectedPin: second.certificateSHA256, generation: generation)
            })
            DispatchQueue.global().asyncAfter(deadline: .now() + 40) { collector.timeout() }
        }
        server.cancel(); client.cancel()
        try await a.deleteAfterRevocation(); try await b.deleteAfterRevocation()
        XCTAssertEqual(results, [true, true])
    }
    func testExpiredIdentityIsNotSilentlyReplaced() async throws {
        let provisioner = PeerIdentityProvisioner(namespace: "orivyn.ci.expired." + UUID().uuidString)
        let now = Date()
        _ = try await provisioner.loadOrCreate(now: now)
        do {
            _ = try await provisioner.loadOrCreate(now: now.addingTimeInterval(31*24*60*60))
            XCTFail("expired identity must require explicit reset and re-pairing")
        } catch {}
        let original = try await provisioner.load(now: now)
        XCTAssertNotNil(original)
        try await provisioner.deleteAfterRevocation()
    }
}

private final class PairingHandshakeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[Bool], Never>?
    private var results: [Bool] = []
    init(_ continuation: CheckedContinuation<[Bool], Never>) { self.continuation = continuation }
    func record(_ result: Result<PeerTLSProbe.Result, Error>, expectedPin: Data, generation: UUID) {
        let valid: Bool
        switch result {
        case .success(let value): valid = value.peerCertificateSHA256 == expectedPin && value.pairingGeneration == generation
        case .failure: valid = false
        }
        lock.lock()
        guard continuation != nil else { lock.unlock(); return }
        results.append(valid)
        let done = results.count == 2 ? continuation : nil
        if done != nil { continuation = nil }
        let snapshot = results
        lock.unlock()
        done?.resume(returning: snapshot)
    }
    func timeout() {
        lock.lock(); let done = continuation; continuation = nil; lock.unlock()
        done?.resume(returning: [false])
    }
}
