// Candidate integration; the production build deliberately leaves this flag off.
#if ORIVYN_PEER_TLS_SPIKE && canImport(Network) && canImport(Security) && canImport(CryptoKit) && canImport(X509) && os(iOS)
import Foundation
import Observation
import CryptoKit
import UIKit
@preconcurrency import Network

@MainActor @Observable
final class PeerSyncSession {
    enum Direction: String, CaseIterable { case send = "Send selected text", receive = "Receive selected text" }
    enum Failure: Error { case unavailable, invalidEndpoint, invalidOffer, changedReview, revoked }
    private(set) var localFingerprint = ""
    private(set) var localOfferText = ""
    private(set) var localEpoch: UUID?
    private(set) var pendingOffer: PeerPairingOffer?
    private(set) var approval: ApprovedPeerPairing?
    private(set) var enabled = false
    private(set) var preparing = false
    private(set) var revoking = false
    private(set) var failure: String?
    private(set) var listeningPort: UInt16?
    private(set) var direction: Direction = .send
    private(set) var endpointDescription = ""
    private let store: SQLiteConversationStore
    private let provisioner: PeerIdentityProvisioner
    private let snapshot: PeerAutomaticSyncController.Snapshot
    private let receive: PeerAutomaticSyncController.Receive
    private var identity: ProvisionedPeerIdentity?
    private var pairing: PeerPairingCoordinator?
    private var controller: PeerAutomaticSyncController?
    private var generation = UUID()
    private var lifecycleRevision = UUID()
    private var foreground = false
    private var protectedDataAvailable = false
    private var revokedApproval: ApprovedPeerPairing?

    /// Internal injection isolates Keychain namespaces in native tests. The app
    /// creates one session and retains this default provisioner for its lifetime.
    init(store: SQLiteConversationStore,
         provisioner: PeerIdentityProvisioner = PeerIdentityProvisioner(),
         snapshot: @escaping PeerAutomaticSyncController.Snapshot,
         receive: @escaping PeerAutomaticSyncController.Receive) {
        self.store = store; self.provisioner = provisioner
        self.snapshot = snapshot; self.receive = receive
    }

    var status: String {
        if revoking { return "Revoking pairing" }
        if !enabled { return "Off" }
        if !foreground || !protectedDataAvailable { return "Paused while inactive or locked" }
        guard let controller else { return "Off" }
        switch controller.status {
        case .stopped: return "Stopped"
        case .running: return "Connecting or exchanging selected text"
        case .waiting: return "Waiting for the next foreground exchange"
        case .draining: return "Finishing cancellation"
        case .blocked: return "Stopped: review required"
        case .retryLimitReached: return "Stopped: retry limit reached"
        }
    }

    func setForeground(_ value: Bool) {
        foreground = value
        setProtectedDataAvailable(UIApplication.shared.isProtectedDataAvailable)
        if !value { lifecycleRevision = UUID(); cancelReview() }
        reconcile()
    }

    func setProtectedDataAvailable(_ value: Bool) {
        protectedDataAvailable = value
        if !value { lifecycleRevision = UUID(); cancelReview() }
        reconcile()
    }

    /// Explicit action only. No saved preference ever creates identity or trust.
    func prepareOffer(conversations: [Conversation], sourceIDs: Set<UUID>) async throws {
        guard !preparing, !revoking, approval == nil, foreground, protectedDataAvailable,
              sourceIDs.count <= 100 else { throw Failure.unavailable }
        let selected = conversations.filter { sourceIDs.contains($0.id) }
        guard selected.count == sourceIDs.count else { throw Failure.invalidOffer }
        preparing = true
        defer { preparing = false }
        let revision = lifecycleRevision
        let loaded = try await provisioner.loadOrCreate()
        let epoch = try await store.textReceiveEpoch()
        try Task.checkCancellation()
        guard revision == lifecycleRevision, foreground, protectedDataAvailable else { throw CancellationError() }
        identity = loaded; localFingerprint = loaded.fingerprint; localEpoch = epoch
        if pairing == nil {
            pairing = PeerPairingCoordinator(localCertificateSHA256: loaded.certificateSHA256,
                certificateSHA256: { Data(SHA256.hash(data: $0)) })
        }
        let entries = selected.map {
            PeerPairingOffer.Conversation(id: $0.id, title: safeOfferTitle($0.title))
        }
        let offer = loaded.offer(generation: generation, receiverEpoch: epoch, offeredConversations: entries)
        try offer.validate()
        localOfferText = String(decoding: try JSONEncoder().encode(offer), as: UTF8.self)
    }

    private func safeOfferTitle(_ title: String) -> String {
        let clean = title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        var result = ""
        for scalar in clean {
            let next = result + String(scalar)
            if next.utf8.count > 240 { break }
            result = next
        }
        return result.isEmpty ? "Conversation" : result
    }

    func review(text: String, direction: Direction, host: String, port: String) throws {
        guard foreground, protectedDataAvailable, !preparing, !revoking, revokedApproval == nil,
              approval == nil, let pairing, identity != nil,
              text.utf8.count <= 65_536 else { throw Failure.unavailable }
        guard let portValue = UInt16(port), portValue > 0 else { throw Failure.invalidEndpoint }
        if direction == .send {
            let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.count <= 253,
                  !value.contains(where: { $0.isWhitespace || $0 == "/" }) else { throw Failure.invalidEndpoint }
        }
        let offer = try PeerPairingOffer.decode(Data(text.utf8))
        guard offer.receiverEpoch != nil else { throw Failure.invalidOffer }
        try pairing.review(offer)
        self.direction = direction
        self.endpointDescription = direction == .send ? "\(host):\(portValue)" : "Local port \(portValue)"
        route = direction == .send
            ? .send(.hostPort(host: .init(host.trimmingCharacters(in: .whitespacesAndNewlines)),
                             port: NWEndpoint.Port(rawValue: portValue)!))
            : .receive(NWEndpoint.Port(rawValue: portValue)!)
        pendingOffer = offer
        // A responder's reply must use the initiator's generation.
        generation = offer.pairingGeneration
        localOfferText = ""
    }

    private var route: PeerAutomaticSyncController.Route?
    func cancelReview() { pairing?.cancelReview(); pendingOffer = nil }

    func approve(fingerprint: String, sourceIDs: Set<UUID>) async throws {
        guard foreground, protectedDataAvailable, !revoking, revokedApproval == nil,
              let pairing, let pendingOffer, let identity, let route else { throw Failure.unavailable }
        let revision = lifecycleRevision
        let epoch: UUID
        if direction == .receive {
            guard sourceIDs.isSubset(of: Set(pendingOffer.offeredConversations.map(\.id))),
                  let localEpoch else { throw Failure.invalidOffer }
            epoch = localEpoch
        } else {
            guard let destination = pendingOffer.receiverEpoch else { throw Failure.invalidOffer }
            epoch = destination
            // Explicitly checked local IDs; the remote offer grants no read authority.
            _ = try await snapshot(sourceIDs)
        }
        let pin = Data(SHA256.hash(data: pendingOffer.certificateDER))
        guard try await !store.isTextPeerRevoked(peerCertificateSHA256: pin,
                    pairingGeneration: pendingOffer.pairingGeneration) else { throw Failure.revoked }
        try Task.checkCancellation()
        guard revision == lifecycleRevision, foreground, protectedDataAvailable,
              self.pendingOffer == pendingOffer else { throw Failure.changedReview }
        let approved = try pairing.approve(independentlyVerifiedFingerprint: fingerprint,
            sourceIDs: sourceIDs, receiverEpoch: epoch)
        self.approval = approved; self.pendingOffer = nil
        controller = PeerAutomaticSyncController(store: store, route: route,
            currentAuthorization: { [weak self] in self?.currentAuthorization },
            makeProbe: { [weak self] authorization in
                guard let self, self.currentAuthorization == authorization,
                      self.approval == approved else { throw Failure.changedReview }
                return PeerTLSProbe(pair: try PeerTLSProbePair(identity: identity.identity,
                    scannedPeerSHA256: approved.peerCertificateSHA256,
                    peerCertificateDER: approved.peerCertificateDER,
                    generation: approved.pairingGeneration))
            }, snapshot: snapshot, receive: { [weak self] authorization, channel in
                guard let self, self.currentAuthorization == authorization else {
                    channel.cancel(); throw Failure.changedReview
                }
                try await self.receive(authorization, channel)
            },
            listenerReady: { [weak self] port in
                Task { @MainActor in
                    guard let self, self.enabled, self.approval == approved else { return }
                    self.listeningPort = port.rawValue
                }
            })
        // Approval is separate from the explicit enable action.
        enabled = false; failure = nil
    }

    private var currentAuthorization: ForegroundSyncCoordinator.Authorization? {
        guard enabled, foreground, protectedDataAvailable, !revoking else { return nil }
        return reviewedAuthorization
    }
    private var reviewedAuthorization: ForegroundSyncCoordinator.Authorization? {
        guard !revoking, let approval else { return nil }
        return .init(peerCertificateSHA256: approval.peerCertificateSHA256,
            localCertificateSHA256: approval.localCertificateSHA256,
            consentRevision: approval.consentRevision, pairingGeneration: approval.pairingGeneration,
            receiverEpoch: approval.receiverEpoch, approvedSourceIDs: approval.approvedSourceIDs)
    }
    func setEnabled(_ value: Bool) {
        guard approval != nil, !revoking else { enabled = false; reconcile(); return }
        enabled = value
        if !value { listeningPort = nil }
        reconcile()
    }
    func retry() { guard currentAuthorization != nil else { return }; controller?.retry() }
    private func reconcile() {
        controller?.update(.init(enabled: enabled, foreground: foreground,
            protectedDataAvailable: protectedDataAvailable, authorization: reviewedAuthorization))
    }

    /// Revoke memory synchronously, then persist before allowing a new review.
    /// A failed durable revocation stays blocked and can be explicitly retried.
    func revoke() async {
        guard !revoking else { return }
        let old = approval ?? revokedApproval
        enabled = false; controller?.stop()
        approval = nil; pairing?.revoke(); pendingOffer = nil
        listeningPort = nil; lifecycleRevision = UUID()
        guard let old else { generation = UUID(); localOfferText = ""; return }
        revokedApproval = old; revoking = true
        defer { revoking = false }
        do {
            try await store.revokeTextPeer(peerCertificateSHA256: old.peerCertificateSHA256,
                                          pairingGeneration: old.pairingGeneration)
            revokedApproval = nil; controller = nil; route = nil
            generation = UUID(); localOfferText = ""; failure = nil
        } catch {
            failure = "Pairing stopped, but durable revocation failed. Retry revocation before pairing again."
        }
    }
}
#endif
