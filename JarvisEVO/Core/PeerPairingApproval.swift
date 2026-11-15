import Foundation

/// Public certificate only. Receiving this document NEVER establishes trust.
struct PeerPairingOffer: Codable, Equatable, Sendable {
    let version: Int
    let pairingGeneration: UUID
    let certificateDER: Data
    struct Conversation: Codable, Equatable, Sendable, Identifiable {
        let id: UUID
        let title: String
    }
    /// Untrusted proposals, never restored consent or authenticated provenance.
    let receiverEpoch: UUID?
    let offeredConversations: [Conversation]
    init(version: Int, pairingGeneration: UUID, certificateDER: Data,
         receiverEpoch: UUID? = nil, offeredConversations: [Conversation] = []) {
        self.version = version; self.pairingGeneration = pairingGeneration
        self.certificateDER = certificateDER; self.receiverEpoch = receiverEpoch
        self.offeredConversations = offeredConversations
    }
    private enum CodingKeys: String, CodingKey { case version, pairingGeneration, certificateDER, receiverEpoch, offeredConversations }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        pairingGeneration = try values.decode(UUID.self, forKey: .pairingGeneration)
        certificateDER = try values.decode(Data.self, forKey: .certificateDER)
        receiverEpoch = try values.decodeIfPresent(UUID.self, forKey: .receiverEpoch)
        offeredConversations = try values.decodeIfPresent([Conversation].self, forKey: .offeredConversations) ?? []
    }
    static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count <= 64_000 else { throw PeerPairingCoordinator.Failure.invalidOffer }
        let offer = try JSONDecoder().decode(Self.self, from: bytes)
        try offer.validate()
        return offer
    }
    func validate() throws {
        guard version == 1, (1...16_384).contains(certificateDER.count),
              offeredConversations.count <= 100,
              Set(offeredConversations.map(\.id)).count == offeredConversations.count,
              offeredConversations.allSatisfy({ (1...240).contains($0.title.utf8.count)
                  && !$0.title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else {
            throw PeerPairingCoordinator.Failure.invalidOffer
        }
    }
}

/// In-memory consent; not Codable, not constructible from a network document.
/// Persistence and the database revocation gate remain responsibilities of the owner.
struct ApprovedPeerPairing: Equatable, Sendable {
    let peerCertificateSHA256: Data
    let localCertificateSHA256: Data
    let pairingGeneration: UUID
    let receiverEpoch: UUID
    let approvedSourceIDs: Set<UUID>
    let consentRevision: UUID
    let peerCertificateDER: Data
}

@MainActor
final class PeerPairingCoordinator {
    enum Failure: Error { case invalidOffer, invalidIdentity, alreadyPaired, revoked, noPendingOffer, fingerprintMismatch, invalidScope }
    private(set) var approved: ApprovedPeerPairing?
    private(set) var pending: PeerPairingOffer?
    private(set) var localCertificateSHA256: Data
    private var retiredGenerations = Set<UUID>()
    private let certificateSHA256: (Data) throws -> Data

    /// Production must supply SHA256 of certificate DER, not a peer-declared digest.
    init(localCertificateSHA256: Data, certificateSHA256: @escaping (Data) throws -> Data) {
        self.localCertificateSHA256 = localCertificateSHA256
        self.certificateSHA256 = certificateSHA256
    }

    func review(_ offer: PeerPairingOffer) throws {
        guard approved == nil else { throw Failure.alreadyPaired }
        pending = nil
        try offer.validate()
        guard localCertificateSHA256.count == 32 else { throw Failure.invalidIdentity }
        guard !retiredGenerations.contains(offer.pairingGeneration) else { throw Failure.revoked }
        let digest = try certificateSHA256(offer.certificateDER)
        guard digest.count == 32, digest != localCertificateSHA256 else { throw Failure.invalidIdentity }
        pending = offer
    }

    /// The full fingerprint must come from the OTHER device's trusted display,
    /// never from the same offer being imported. No shortened-code comparison.
    @discardableResult
    func approve(independentlyVerifiedFingerprint: String, sourceIDs: Set<UUID>, receiverEpoch: UUID) throws -> ApprovedPeerPairing {
        guard approved == nil, let offer = pending else { throw Failure.noPendingOffer }
        guard (1...100).contains(sourceIDs.count) else { throw Failure.invalidScope }
        let hex = independentlyVerifiedFingerprint.lowercased()
        guard hex.utf8.count == 64, hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw Failure.fingerprintMismatch
        }
        let digest = try certificateSHA256(offer.certificateDER)
        guard digest.count == 32, hex == digest.map({ String(format: "%02x", $0) }).joined() else {
            throw Failure.fingerprintMismatch
        }
        let consent = ApprovedPeerPairing(peerCertificateSHA256: digest,
            localCertificateSHA256: localCertificateSHA256, pairingGeneration: offer.pairingGeneration,
            receiverEpoch: receiverEpoch, approvedSourceIDs: sourceIDs, consentRevision: UUID(),
            peerCertificateDER: offer.certificateDER)
        approved = consent; pending = nil
        return consent
    }

    func cancelReview() { pending = nil }

    /// Owner must cancel transfers and durably revoke the database generation.
    /// This invalidates memory immediately even if that durable operation fails.
    func revoke() {
        if let approved { retiredGenerations.insert(approved.pairingGeneration) }
        if let pending { retiredGenerations.insert(pending.pairingGeneration) }
        approved = nil; pending = nil
    }

    func replaceLocalIdentity(certificateSHA256: Data) {
        revoke()
        localCertificateSHA256 = certificateSHA256
    }
}
