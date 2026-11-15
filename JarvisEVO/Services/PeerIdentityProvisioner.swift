// Remains experimental until iOS provisioning and two-device lifecycle gates pass.
#if ORIVYN_PEER_TLS_SPIKE && canImport(Security) && canImport(CryptoKit) && canImport(X509)
import Foundation
@preconcurrency import Security
import CryptoKit
import X509
import SwiftASN1

struct ProvisionedPeerIdentity: @unchecked Sendable {
    let identity: SecIdentity
    let certificateDER: Data
    var certificateSHA256: Data { Data(SHA256.hash(data: certificateDER)) }
    var fingerprint: String { certificateSHA256.map { String(format: "%02x", $0) }.joined() }
    func offer(generation: UUID, receiverEpoch: UUID? = nil,
               offeredConversations: [PeerPairingOffer.Conversation] = []) -> PeerPairingOffer {
        PeerPairingOffer(version: 1, pairingGeneration: generation, certificateDER: certificateDER,
                         receiverEpoch: receiverEpoch, offeredConversations: offeredConversations)
    }
}

/// Serializes this device's Keychain identity lifecycle. Keys never enter an offer,
/// UserDefaults, logs or backup payload. Call only after explicit pairing setup.
actor PeerIdentityProvisioner {
    enum Failure: Error { case keychain(OSStatus), incompleteIdentity, invalidIdentity, randomFailure }
    private let tag: Data
    private let label: String

    init(namespace: String = "app.jarvisevo.peer-tls.v1") {
        tag = Data(namespace.utf8)
        label = namespace + ".certificate"
    }

    func loadOrCreate(now: Date = Date()) throws -> ProvisionedPeerIdentity {
        if let existing = try load(now: now) { return existing }
        // A leftover key means interrupted provisioning. Never silently replace it.
        var keyResult: CFTypeRef?
        let keyStatus = SecItemCopyMatching(keyQuery(returnReference: true) as CFDictionary, &keyResult)
        guard keyStatus == errSecItemNotFound else {
            if keyStatus == errSecSuccess { throw Failure.incompleteIdentity }
            throw Failure.keychain(keyStatus)
        }
        var failure: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: tag,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecAttrSynchronizable: false
            ] as [CFString: Any]
        ]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &failure) else {
            let code = failure.map { CFErrorGetCode($0.takeRetainedValue()) } ?? Int(errSecInternalComponent)
            throw Failure.keychain(OSStatus(code))
        }
        // Keep a partially created identity on failure. An explicit reset is required.
        let signingKey = try Certificate.PrivateKey(key)
        var serial = [UInt8](repeating: 0, count: 20)
        guard SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial) == errSecSuccess else { throw Failure.randomFailure }
        serial[0] &= 0x7f; serial[0] |= 1
        let name = try DistinguishedName { CommonName("Orivyn peer " + UUID().uuidString) }
        let certificate = try Certificate(version: .v3, serialNumber: .init(bytes: serial),
            publicKey: signingKey.publicKey, notValidBefore: now.addingTimeInterval(-60),
            notValidAfter: now.addingTimeInterval(30 * 24 * 60 * 60),
            issuer: name, subject: name, signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
                try ExtendedKeyUsage([.serverAuth, .clientAuth])
            }, issuerPrivateKey: signingKey)
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        let der = Data(serializer.serializedBytes)
        guard let secCertificate = SecCertificateCreateWithData(nil, der as CFData) else { throw Failure.invalidIdentity }
        let add: [CFString: Any] = [
            kSecClass: kSecClassCertificate, kSecValueRef: secCertificate,
            kSecAttrLabel: label, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: false
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let result = try load(now: now) else { throw Failure.incompleteIdentity }
        return result
    }

    func load(now: Date = Date()) throws -> ProvisionedPeerIdentity? {
        var certificateResult: CFTypeRef?
        let certificateQuery: [CFString: Any] = [
            kSecClass: kSecClassCertificate, kSecAttrLabel: label,
            kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitOne,
            kSecAttrSynchronizable: false
        ]
        let status = SecItemCopyMatching(certificateQuery as CFDictionary, &certificateResult)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let certificateResult, CFGetTypeID(certificateResult) == SecCertificateGetTypeID() else { throw Failure.invalidIdentity }
        let certificate = certificateResult as! SecCertificate
        let parsed = try Certificate(certificate)
        guard parsed.notValidBefore <= now, now < parsed.notValidAfter,
              parsed.issuer == parsed.subject, parsed.signatureAlgorithm == .ecdsaWithSHA256,
              parsed.publicKey.isValidSignature(parsed.signature, for: parsed),
              try parsed.extensions.basicConstraints == .notCertificateAuthority,
              let usage = try parsed.extensions.keyUsage, usage.digitalSignature, !usage.keyCertSign,
              let extended = try parsed.extensions.extendedKeyUsage,
              extended.contains(.serverAuth), extended.contains(.clientAuth) else { throw Failure.invalidIdentity }
        var result: CFTypeRef?
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity, kSecAttrLabel: label,
            kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitOne,
            kSecAttrSynchronizable: false
        ]
        let identityStatus = SecItemCopyMatching(query as CFDictionary, &result)
        guard identityStatus == errSecSuccess else { throw Failure.keychain(identityStatus) }
        guard let result, CFGetTypeID(result) == SecIdentityGetTypeID() else { throw Failure.incompleteIdentity }
        let identity = result as! SecIdentity
        var identityCertificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &identityCertificate) == errSecSuccess,
              let identityCertificate, SecCertificateCopyData(identityCertificate) as Data == SecCertificateCopyData(certificate) as Data else {
            throw Failure.invalidIdentity
        }
        // Check the Keychain identity resolves to this namespace's key, not another
        // certificate with a reused label.
        var expected: CFTypeRef?
        let keyStatus = SecItemCopyMatching(keyQuery(returnReference: true) as CFDictionary, &expected)
        guard keyStatus == errSecSuccess else { throw Failure.keychain(keyStatus) }
        guard let expected, CFGetTypeID(expected) == SecKeyGetTypeID() else { throw Failure.incompleteIdentity }
        var identityKey: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &identityKey) == errSecSuccess, let identityKey,
              CFEqual(identityKey, expected) else { throw Failure.invalidIdentity }
        return ProvisionedPeerIdentity(identity: identity, certificateDER: SecCertificateCopyData(certificate) as Data)
    }

    /// Owner MUST cancel all transfers and durably revoke every associated pairing
    /// before reset. A new certificate requires a new independently approved pairing.
    func deleteAfterRevocation() throws {
        let certificateQuery: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecAttrLabel: label, kSecAttrSynchronizable: false]
        let certStatus = SecItemDelete(certificateQuery as CFDictionary)
        guard certStatus == errSecSuccess || certStatus == errSecItemNotFound else { throw Failure.keychain(certStatus) }
        let keyStatus = SecItemDelete(keyQuery(returnReference: false) as CFDictionary)
        guard keyStatus == errSecSuccess || keyStatus == errSecItemNotFound else { throw Failure.keychain(keyStatus) }
    }

    private func keyQuery(returnReference: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassKey, kSecAttrApplicationTag: tag,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrSynchronizable: false
        ]
        if returnReference { query[kSecReturnRef] = true; query[kSecMatchLimit] = kSecMatchLimitOne }
        return query
    }
}
#endif
