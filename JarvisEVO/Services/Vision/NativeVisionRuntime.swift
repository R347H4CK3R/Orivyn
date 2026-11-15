#if ORIVYN_NATIVE_VISION
import Foundation

/// All resources are single-use. VisionSession supplies the heavy-work lease;
/// the private pair lease is retained until worker exit and native destruction.
actor NativeVisionRuntime: LocalVisionRuntime {
    enum Failure: Error, LocalizedError {
        case native(Int32), output, closed
        var errorDescription: String? {
            switch self {
            case .native(let status): "Image analysis stopped (\(status)). Try a clearer image or a shorter question."
            case .output: "The model did not produce a complete readable answer."
            case .closed: "This image analysis has already closed. Start a new analysis."
            }
        }
    }
    private let store: VisionPairStore
    private nonisolated let worker: VisionWorker
    private var lease: VisionPairStore.Lease?
    private var started = false
    private var isClosing = false
    init(store: VisionPairStore) throws { self.store = store; worker = try VisionWorker() }
    func run(encodedImage: Data, question: String) async throws -> String {
        guard !started, !isClosing else { throw Failure.closed }
        started = true
        try Task.checkCancellation()
        let image = try ImageBoundary.decode(encodedImage)
        let pair = try await store.acquire()
        lease = pair
        try Task.checkCancellation()
        guard !isClosing else { throw CancellationError() }
        let result = await worker.run(image: image, question: question, model: pair.model.path, projector: pair.projector.path)
        try Task.checkCancellation()
        guard result.status == 0 else { throw Failure.native(result.status) }
        guard result.report.tokens < 128, let text = result.text, !text.isEmpty else { throw Failure.output }
        return text
    }
    nonisolated func cancel() { worker.cancel() }
    func close() async -> Bool {
        isClosing = true
        await worker.close()
        // VisionSession always waits for run before close. This actor additionally
        // prevents new runs while teardown is suspended.
        if let lease { await store.release(lease); self.lease = nil }
        return worker.isClosed
    }
}
#endif
