import Foundation

/// Foreground-only orchestration. This does not authenticate a peer or grant access:
/// the operation must revalidate the durable pairing, epoch and reviewed scope at
/// its transaction boundary, and cancel its channel when its Task is cancelled.
@MainActor
final class ForegroundSyncCoordinator {
    struct Authorization: Equatable, Sendable {
        let peerCertificateSHA256: Data
        let localCertificateSHA256: Data
        let consentRevision: UUID
        let pairingGeneration: UUID
        let receiverEpoch: UUID
        let approvedSourceIDs: Set<UUID>

        var isValid: Bool {
            peerCertificateSHA256.count == 32 && localCertificateSHA256.count == 32 &&
            peerCertificateSHA256 != localCertificateSHA256 &&
            (1...100).contains(approvedSourceIDs.count)
        }
    }

    struct Conditions: Equatable, Sendable {
        var enabled = false
        var foreground = false
        var protectedDataAvailable = false
        var authorization: Authorization?

        var eligible: Authorization? {
            guard enabled, foreground, protectedDataAvailable,
                  let authorization, authorization.isValid else { return nil }
            return authorization
        }
    }

    enum Outcome: Sendable {
        case success
        /// Only transport availability failures belong here. Authentication,
        /// revocation, conflict and invalid receipt failures must be blocked.
        case retryableFailure
        case blocked
    }

    enum Status: Equatable {
        case stopped, running, waiting, draining, blocked, retryLimitReached
    }

    struct Policy {
        let intervalNanoseconds: UInt64
        let retryNanoseconds: [UInt64]
        init(intervalNanoseconds: UInt64 = 30_000_000_000,
             retryNanoseconds: [UInt64] = [2_000_000_000, 5_000_000_000, 15_000_000_000]) {
            // Avoid busy loops, unbounded retry lists and arithmetic overflow.
            self.intervalNanoseconds = min(max(intervalNanoseconds, 1_000_000), 3_600_000_000_000)
            self.retryNanoseconds = Array(retryNanoseconds.prefix(3)).map {
                min(max($0, 1_000_000), 60_000_000_000)
            }
        }
    }

    typealias Operation = @MainActor @Sendable (Authorization) async -> Outcome
    typealias Sleep = @Sendable (UInt64) async throws -> Void

    private let operation: Operation
    private let sleep: Sleep
    private let policy: Policy
    private var conditions = Conditions()
    private var task: Task<Void, Never>?
    private var activeAuthorization: Authorization?
    private var haltedAuthorization: Authorization?
    private var haltedStatus: Status = .blocked
    private var cancelled = false
    private var consecutiveFailures = 0
    private var pendingDelay: UInt64?
    private(set) var status: Status = .stopped

    init(policy: Policy = Policy(),
         sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) },
         operation: @escaping Operation) {
        self.policy = policy
        self.sleep = sleep
        self.operation = operation
    }

    /// Call on enable/disable, scene activation, protected-data availability,
    /// scope edits, pairing replacement and revocation. Revocation supplies nil.
    /// A cancelled task keeps its slot until it returns, including across a rapid
    /// disable/re-enable. This intentionally fails closed for a hung operation.
    func update(_ newConditions: Conditions) {
        if conditions.authorization != newConditions.authorization {
            haltedAuthorization = nil
            consecutiveFailures = 0
            pendingDelay = nil
        }
        conditions = newConditions
        if task != nil, activeAuthorization != conditions.eligible {
            cancelled = true
            status = .draining
            task?.cancel()
        }
        reconcile()
    }

    /// Explicit user retry only; lifecycle churn must not reset retry limits.
    func retry() {
        guard task == nil, conditions.eligible != nil else { return }
        haltedAuthorization = nil
        consecutiveFailures = 0
        pendingDelay = nil
        reconcile()
    }

    private func reconcile() {
        guard task == nil else { return }
        guard let authorization = conditions.eligible else {
            status = .stopped
            return
        }
        guard haltedAuthorization != authorization else {
            status = haltedStatus
            return
        }
        activeAuthorization = authorization
        cancelled = false
        status = .running
        task = Task { [weak self] in
            await self?.run(authorization)
        }
    }

    private func run(_ authorization: Authorization) async {
        while !Task.isCancelled && !cancelled && conditions.eligible == authorization {
            // Retain the full pending delay across lifecycle cancellation. A
            // resume may postpone a retry, but can never accelerate it.
            if let delay = pendingDelay {
                status = .waiting
                do { try await sleep(delay) }
                catch {
                    if !Task.isCancelled && !cancelled {
                        haltedAuthorization = authorization
                        haltedStatus = .blocked
                        status = haltedStatus
                    }
                    break
                }
                guard !Task.isCancelled, !cancelled, conditions.eligible == authorization else { break }
                pendingDelay = nil
            }
            status = .running
            let outcome = await operation(authorization)
            guard !Task.isCancelled, !cancelled, conditions.eligible == authorization else { break }
            switch outcome {
            case .success:
                consecutiveFailures = 0
                pendingDelay = policy.intervalNanoseconds
            case .retryableFailure:
                guard consecutiveFailures < policy.retryNanoseconds.count else {
                    haltedAuthorization = authorization
                    haltedStatus = .retryLimitReached
                    status = haltedStatus
                    finish()
                    return
                }
                pendingDelay = policy.retryNanoseconds[consecutiveFailures]
                consecutiveFailures += 1
            case .blocked:
                haltedAuthorization = authorization
                haltedStatus = .blocked
                status = haltedStatus
                finish()
                return
            }
        }
        finish()
    }

    private func finish() {
        task = nil
        activeAuthorization = nil
        if cancelled { status = .stopped }
        reconcile()
    }
}
