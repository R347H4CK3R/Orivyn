// Gated until pairing, lifecycle delivery and native transport are integrated.
#if ORIVYN_PEER_TLS_SPIKE && canImport(Network) && canImport(Security) && canImport(CryptoKit)
import Foundation
@preconcurrency import Network

/// One explicitly selected direction and endpoint. No discovery or implicit
/// bidirectional approval. receiverEpoch denotes the destination's epoch.
@MainActor
final class PeerAutomaticSyncController {
    typealias Authorization = ForegroundSyncCoordinator.Authorization
    enum Route {
        case send(NWEndpoint)
        case receive(NWEndpoint.Port)
    }
    enum Failure: Error { case authorityChanged, invalidScope, invalidChannel, pendingScopeChanged }
    typealias CurrentAuthorization = @MainActor () -> Authorization?
    typealias MakeProbe = @MainActor (Authorization) throws -> PeerTLSProbe
    typealias Snapshot = @MainActor (Set<UUID>) async throws -> ReviewedTextSnapshot
    /// The app must acquire its exclusive history owner before calling
    /// PeerTextRevisionExchange.receive, then reload before releasing that owner.
    typealias Receive = @MainActor (Authorization, PeerTLSProbe.AuthenticatedChannel) async throws -> Void

    private let store: SQLiteConversationStore
    private let route: Route
    private let currentAuthorization: CurrentAuthorization
    private let makeProbe: MakeProbe
    private let snapshot: Snapshot
    private let receive: Receive
    private let listenerReady: @Sendable (NWEndpoint.Port) -> Void
    private var lastSentAuthorization: Authorization?
    private var lastSentConversations: [Conversation]?
    private lazy var scheduler = ForegroundSyncCoordinator(policy: schedulerPolicy) { [weak self] authorization in
        guard let self else { return .blocked }
        return await self.exchange(authorization)
    }

    private var schedulerPolicy: ForegroundSyncCoordinator.Policy {
        switch route {
        case .send: return .init()
        case .receive: return .init(intervalNanoseconds: 1_000_000_000)
        }
    }

    init(store: SQLiteConversationStore, route: Route,
         currentAuthorization: @escaping CurrentAuthorization,
         makeProbe: @escaping MakeProbe,
         snapshot: @escaping Snapshot,
         receive: @escaping Receive,
         listenerReady: @escaping @Sendable (NWEndpoint.Port) -> Void = { _ in }) {
        self.store = store
        self.route = route
        self.currentAuthorization = currentAuthorization
        self.makeProbe = makeProbe
        self.snapshot = snapshot
        self.receive = receive
        self.listenerReady = listenerReady
    }

    var status: ForegroundSyncCoordinator.Status { scheduler.status }
    func update(_ conditions: ForegroundSyncCoordinator.Conditions) { scheduler.update(conditions) }
    func retry() { scheduler.retry() }
    func stop() { scheduler.update(.init()) }

    private func requireAuthority(_ authorization: Authorization) async throws {
        try Task.checkCancellation()
        guard authorization.isValid, currentAuthorization() == authorization else { throw Failure.authorityChanged }
        guard try await !store.isTextPeerRevoked(peerCertificateSHA256: authorization.peerCertificateSHA256,
                                                 pairingGeneration: authorization.pairingGeneration) else {
            throw Failure.authorityChanged
        }
        try Task.checkCancellation()
        guard currentAuthorization() == authorization else { throw Failure.authorityChanged }
    }

    private func exchange(_ authorization: Authorization) async -> ForegroundSyncCoordinator.Outcome {
        do {
            try await requireAuthority(authorization)
            let transfer: StagedTextSend?
            switch route {
            case .send:
                transfer = try await outgoing(authorization)
                if transfer == nil { return .success }
            case .receive:
                guard try await store.textReceiveEpoch() == authorization.receiverEpoch else { throw Failure.authorityChanged }
                transfer = nil
            }
            try await requireAuthority(authorization)
            let probe = try makeProbe(authorization)
            return try await withTaskCancellationHandler {
                defer { probe.cancel() }
                try Task.checkCancellation()
                let channel = try await connect(probe)
                defer { channel.cancel() }
                try await requireAuthority(authorization)
                guard channel.localCertificateSHA256 == authorization.localCertificateSHA256,
                      channel.peerCertificateSHA256 == authorization.peerCertificateSHA256,
                      channel.pairingGeneration == authorization.pairingGeneration else { throw Failure.invalidChannel }
                switch route {
                case .send:
                    guard let transfer else { throw Failure.invalidScope }
                    _ = try await PeerTextRevisionExchange.send(transferID: transfer.identity.transfer,
                                                                store: store, over: channel)
                    try await requireAuthority(authorization)
                    lastSentAuthorization = authorization
                    lastSentConversations = try TextRevisionEnvelope.decodeCanonical(transfer.payload).records.map(\.incoming)
                case .receive:
                    // The supplied closure is the mandatory AppModel ownership
                    // boundary. Never call the raw database receive here.
                    try await receive(authorization, channel)
                    try await requireAuthority(authorization)
                }
                return .success
            } onCancel: {
                probe.cancel()
            }
        } catch {
            guard !Task.isCancelled else { return .blocked }
            // The owner is temporarily generating/importing. This does not
            // acknowledge a transfer or reset consecutive transport failures.
            if let failure = error as? PeerTextRevisionExchange.Failure, case .peerBusy = failure {
                return .deferred
            }
            if let failure = error as? TextSnapshotError, case .busy = failure { return .deferred }
            if let failure = error as? PeerTLSProbe.Failure {
                switch failure {
                case .idleTimeout:
                    if case .receive = route { return .deferred }
                    return .blocked
                case .timeout: return .retryableFailure
                default: return .blocked
                }
            }
            // Explicit availability failures only. TLS, DNS, malformed frames,
            // invalid receipts and unknown errors never enter an automatic retry.
            if let failure = error as? NWError, case .posix(let code) = failure {
                switch code {
                case .ECONNREFUSED, .ENETUNREACH, .EHOSTUNREACH, .ETIMEDOUT:
                    return .retryableFailure
                default: break
                }
            }
            return .blocked
        }
    }

    private func connect(_ probe: PeerTLSProbe) async throws -> PeerTLSProbe.AuthenticatedChannel {
        try await withCheckedThrowingContinuation { continuation in
            switch route {
            case .send(let endpoint):
                probe.connectForTransfer(to: endpoint) { continuation.resume(with: $0) }
            case .receive(let port):
                probe.listenForTransfer(on: port, ready: listenerReady) { continuation.resume(with: $0) }
            }
        }
    }

    private func outgoing(_ authorization: Authorization) async throws -> StagedTextSend? {
        // Pending bytes and transfer ID take precedence over fresh edits. Receipts
        // make lost-ack retries idempotent. Never silently discard an old scope.
        let ids = try await store.pendingTextRevisionSendIDs()
        for id in ids {
            try await requireAuthority(authorization)
            guard let pending = try await store.textRevisionSend(id: id), !pending.delivered else { continue }
            let identity = pending.identity
            guard identity.senderCertificateSHA256 == authorization.localCertificateSHA256,
                  identity.receiverCertificateSHA256 == authorization.peerCertificateSHA256,
                  identity.pairingGeneration == authorization.pairingGeneration,
                  identity.receiverEpoch == authorization.receiverEpoch else { continue }
            let sources = Set(try TextRevisionEnvelope.decodeCanonical(pending.payload).records.map { $0.incoming.id })
            guard sources.isSubset(of: authorization.approvedSourceIDs) else { throw Failure.pendingScopeChanged }
            return pending
        }
        try await requireAuthority(authorization)
        let reviewed = try await snapshot(authorization.approvedSourceIDs)
        try await requireAuthority(authorization)
        guard Set(reviewed.conversations.map(\.id)) == authorization.approvedSourceIDs else { throw Failure.invalidScope }
        // Avoid filling the durable outbox with unchanged periodic snapshots.
        // On restart one repeat is safe; exact receiver ancestry remains checked.
        if lastSentAuthorization == authorization,
           lastSentConversations == reviewed.conversations { return nil }
        return try await store.stageTextRevisionSend(reviewed,
            senderCertificateSHA256: authorization.localCertificateSHA256,
            peerCertificateSHA256: authorization.peerCertificateSHA256,
            pairingGeneration: authorization.pairingGeneration,
            receiverEpoch: authorization.receiverEpoch)
    }
}
#endif
