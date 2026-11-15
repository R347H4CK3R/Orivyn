import XCTest
import Foundation
import Security
import CryptoKit
import X509
import SwiftASN1
import Network
@testable import PairingPolicy

final class PeerIdentityProvisionerTests: XCTestCase, @unchecked Sendable {
    func testExactCertificateLabelUpdatePreservesSearchableLabel() throws {
        let label = "orivyn.ci.der-label." + UUID().uuidString
        var error: Unmanaged<CFError>?
        let key = try XCTUnwrap(SecKeyCreateRandomKey([
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256
        ] as CFDictionary, &error))
        let privateKey = try Certificate.PrivateKey(key)
        let name = try DistinguishedName { CommonName("Different certificate subject " + UUID().uuidString) }
        let now = Date()
        let certificate = try Certificate(version: .v3, serialNumber: .init(bytes: [1, 2, 3]),
            publicKey: privateKey.publicKey, notValidBefore: now.addingTimeInterval(-60),
            notValidAfter: now.addingTimeInterval(3600), issuer: name, subject: name,
            signatureAlgorithm: .ecdsaWithSHA256, extensions: Certificate.Extensions {},
            issuerPrivateKey: privateKey)
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        let der = Data(serializer.serializedBytes)
        let reference = try XCTUnwrap(SecCertificateCreateWithData(nil, der as CFData))
        let add: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValueRef: reference,
            kSecAttrLabel: label, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: false]
        // A second certificate catches accidental class-wide label updates.
        let decoyLabel = "orivyn.ci.decoy." + UUID().uuidString
        let decoyName = try DistinguishedName { CommonName("Orivyn decoy " + UUID().uuidString) }
        let decoyCertificate = try Certificate(version: .v3, serialNumber: .init(bytes: [4, 5, 6]),
            publicKey: privateKey.publicKey, notValidBefore: now.addingTimeInterval(-60),
            notValidAfter: now.addingTimeInterval(3600), issuer: decoyName, subject: decoyName,
            signatureAlgorithm: .ecdsaWithSHA256, extensions: Certificate.Extensions {},
            issuerPrivateKey: privateKey)
        var decoySerializer = DER.Serializer(); try decoySerializer.serialize(decoyCertificate)
        let decoyDER = Data(decoySerializer.serializedBytes)
        let decoyReference = try XCTUnwrap(SecCertificateCreateWithData(nil, decoyDER as CFData))
        let decoyExact: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValueRef: decoyReference]
        XCTAssertEqual(SecItemAdd(decoyExact as CFDictionary, nil), errSecSuccess)
        defer { SecItemDelete(decoyExact as CFDictionary) }
        XCTAssertEqual(SecItemUpdate(decoyExact as CFDictionary, [kSecAttrLabel: decoyLabel] as CFDictionary), errSecSuccess)
        XCTAssertEqual(SecItemAdd(add as CFDictionary, nil), errSecSuccess)
        defer { SecItemDelete([kSecClass: kSecClassCertificate, kSecValueRef: reference] as CFDictionary) }
        let update: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValueRef: reference]
        XCTAssertEqual(SecItemUpdate(update as CFDictionary, [kSecAttrLabel: label] as CFDictionary), errSecSuccess)
        let delete: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecAttrLabel: label,
            kSecAttrSynchronizable: false]
        var decoyResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching([
            kSecClass: kSecClassCertificate, kSecAttrLabel: decoyLabel,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &decoyResult), errSecSuccess)
        let decoyData = try XCTUnwrap(decoyResult)
        XCTAssertEqual(CFGetTypeID(decoyData), CFDataGetTypeID())
        guard CFGetTypeID(decoyData) == CFDataGetTypeID() else { return }
        XCTAssertEqual(decoyData as? Data, decoyDER)
        var query = delete
        query[kSecReturnRef] = true; query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        XCTAssertEqual(status, errSecSuccess)
        let item = try XCTUnwrap(result)
        XCTAssertEqual(CFGetTypeID(item), SecCertificateGetTypeID())
        guard CFGetTypeID(item) == SecCertificateGetTypeID() else { return }
        XCTAssertEqual(SecCertificateCopyData(item as! SecCertificate) as Data, der)
    }
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
