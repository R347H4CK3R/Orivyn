import XCTest
import Foundation
import Security
import CryptoKit
import X509
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
        let signingKey = try Certificate.PrivateKey(XCTUnwrap(key))
        let message = Data("proof-of-possession".utf8)
        let signature = try signingKey.sign(bytes: message, signatureAlgorithm: .ecdsaWithSHA256)
        XCTAssertTrue(certificate.publicKey.isValidSignature(signature, for: message, signatureAlgorithm: .ecdsaWithSHA256))
        try await provisioner.deleteAfterRevocation()
        let removed = try await provisioner.load()
        XCTAssertNil(removed)
        let replacement = try await provisioner.loadOrCreate()
        XCTAssertNotEqual(created.certificateSHA256, replacement.certificateSHA256)
        try await provisioner.deleteAfterRevocation()
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
