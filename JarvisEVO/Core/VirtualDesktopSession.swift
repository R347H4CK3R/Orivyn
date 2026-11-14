import Foundation
import Observation

@MainActor
protocol VirtualDesktopRuntime: AnyObject {
    func startRuntime() -> Bool
    func stopAndWait() async -> Bool
}

/// The outer presentation owns both runtime and lease through asynchronous teardown.
@MainActor @Observable
final class VirtualDesktopSession {
    enum Phase: Equatable { case idle, preparing, running, stopping, finished, blocked }
    private(set) var phase: Phase = .idle
    private(set) var error: String?
    let id = UUID()
    private let model: AppModel
    private let runtime: any VirtualDesktopRuntime
    private var preparation: Task<Void, Never>?
    private var closing: Task<Bool, Never>?

    init(model: AppModel, runtime: any VirtualDesktopRuntime) {
        self.model = model; self.runtime = runtime
    }

    func start() {
        guard phase == .idle else { return }
        phase = .preparing
        preparation = Task { @MainActor [self] in
            do {
                try await model.beginHeavyWork(id: id, kind: .virtualDesktop)
                try Task.checkCancellation()
                guard phase == .preparing, model.heavyWorkLease?.id == id,
                      model.heavyWorkLease?.phase == .ready else { throw CancellationError() }
                guard runtime.startRuntime() else {
                    error = "The local guest could not start. Closing its resources."
                    Task { await self.close() }
                    return
                }
                phase = .running
            } catch {
                // No runtime start has occurred on this path. The resource release
                // await has settled, so this owner can safely end its reservation.
                model.endHeavyWork(id: id)
                if phase != .stopping {
                    self.error = error is CancellationError ? "Start canceled." : error.localizedDescription
                    phase = .finished
                }
            }
        }
    }

    @discardableResult
    func close() async -> Bool {
        if let closing { return await closing.value }
        phase = .stopping
        preparation?.cancel()
        let task = Task { @MainActor [self] in
            await preparation?.value
            let acknowledged = await runtime.stopAndWait()
            if acknowledged {
                model.endHeavyWork(id: id)
                phase = .finished
            } else {
                model.revokeHeavyWork(id: id)
                phase = .blocked
                error = "Runtime shutdown could not be verified. Other heavy tasks remain blocked; restart Orivyn before retrying."
            }
            return acknowledged
        }
        closing = task
        return await task.value
    }
}
