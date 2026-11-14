import Foundation

/// One owner, one drain. A failed acknowledgment never becomes a successful stop.
/// This orders application work; it does not prove immediate WebContent RSS reclamation.
@MainActor
final class VMTeardownCoordinator {
    enum Phase: Equatable { case idle, draining, stopped, failed }
    private(set) var phase: Phase = .idle
    private var task: Task<Bool, Never>?

    @discardableResult
    func stop(runtime: @escaping @MainActor () async -> Bool,
              checkpoint: @escaping @MainActor () async -> Void,
              detach: @escaping @MainActor () -> Void) -> Task<Bool, Never> {
        if let task { return task }
        phase = .draining
        let pending = Task { @MainActor [self] in
            let acknowledged = await runtime()
            await checkpoint()
            detach()
            phase = acknowledged ? .stopped : .failed
            return acknowledged
        }
        task = pending
        return pending
    }
}
