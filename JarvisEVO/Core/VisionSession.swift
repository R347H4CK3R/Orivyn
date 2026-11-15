import Foundation
import Observation

/// Implementations must own their image/model buffers until run has returned.
/// cancel is independent of the native worker queue; close acknowledges release.
protocol LocalVisionRuntime: Sendable {
    func run(encodedImage: Data, question: String) async throws -> String
    func cancel()
    func close() async -> Bool
}

@MainActor
protocol VisionLeaseOwner: AnyObject {
    var heavyWorkLease: LocalHeavyWorkLease? { get }
    func beginHeavyWork(id: UUID, kind: LocalHeavyWorkKind) async throws
    func endHeavyWork(id: UUID)
    func revokeHeavyWork(id: UUID?)
}

/// Single-use owner. No broad-vision UI is enabled by constructing this type.
/// A runtime may be supplied only after model-pair and native capability checks.
@MainActor @Observable
final class VisionSession {
    enum Phase: Equatable { case idle, preparing, running, stopping, finished, blocked }
    private(set) var phase: Phase = .idle
    private(set) var output: String?
    private(set) var error: String?
    let id = UUID()
    private let owner: any VisionLeaseOwner
    private let runtime: any LocalVisionRuntime
    private var operation: Task<Void, Never>?
    private var pendingOutput: String?
    private var discardOutput = false
    private var closing: Task<Bool, Never>?

    init(owner: any VisionLeaseOwner, runtime: any LocalVisionRuntime) {
        self.owner = owner; self.runtime = runtime
    }

    func run(encodedImage: Data, question: String) async {
        guard phase == .idle else { return }
        // Reject before reserving or decoding; metadata/pixel bounds belong to
        // the real runtime's ImageBoundary, never a full-size decode fallback.
        guard !encodedImage.isEmpty, encodedImage.count <= 10 * 1024 * 1024,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              question.utf8.count <= 4096, !question.contains("\0") else {
            error = "Choose one supported image and a question within the input limits."
            _ = await teardown(cancel: true)
            return
        }
        phase = .preparing
        let task = Task { @MainActor [self] in
            do {
                try await owner.beginHeavyWork(id: id, kind: .vision)
                try Task.checkCancellation()
                guard leaseReady, phase == .preparing else { throw CancellationError() }
                phase = .running
                let answer = try await runtime.run(encodedImage: encodedImage, question: question)
                try Task.checkCancellation()
                guard leaseReady, phase == .running else { throw CancellationError() }
                guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      answer.utf8.count <= 16384 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                pendingOutput = answer
            } catch {
                output = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
        operation = task
        await withTaskCancellationHandler {
            await task.value
            _ = await teardown(cancel: false)
        } onCancel: { [runtime] in
            runtime.cancel()
            task.cancel()
        }
        if Task.isCancelled { output = nil }
    }

    private var leaseReady: Bool {
        owner.heavyWorkLease?.id == id && owner.heavyWorkLease?.kind == .vision &&
            owner.heavyWorkLease?.phase == .ready
    }

    /// Call on dismissal, backgrounding or lease revocation. Holding the lease
    /// until close acknowledges release prevents text and vision model overlap.
    @discardableResult
    func close() async -> Bool { await teardown(cancel: true) }

    private func teardown(cancel: Bool) async -> Bool {
        if cancel {
            discardOutput = true; output = nil
            operation?.cancel(); runtime.cancel()
        }
        if let closing { return await closing.value }
        if phase == .idle { phase = .stopping }
        if operation != nil && phase != .finished {
            phase = .stopping
            if cancel { operation?.cancel(); runtime.cancel() }
        }
        let task = Task { @MainActor [self] in
            await operation?.value
            let released = await runtime.close()
            if released {
                if !discardOutput, leaseReady, operation?.isCancelled == false { output = pendingOutput }
                pendingOutput = nil
                owner.endHeavyWork(id: id)
                phase = .finished
            } else {
                output = nil
                owner.revokeHeavyWork(id: id)
                phase = .blocked
                error = "Vision resources could not be released. Restart Orivyn before another memory-intensive task."
            }
            return released
        }
        closing = task
        return await task.value
    }
}
