import Foundation

struct VisionReport: Sendable {
    let status, phase, tokens, positions, image_chunks, callback_count, live_resources: Int32
    init(_ r: ov_report) {
        status = r.status; phase = r.phase; tokens = r.tokens; positions = r.positions
        image_chunks = r.image_chunks; callback_count = r.callback_count; live_resources = r.live_resources
    }
}
struct VisionResult: Sendable {
    let status: Int32
    let output: Data
    let report: VisionReport
    var text: String? { String(data: output, encoding: .utf8) }
    static func rejected(_ status: Int32) -> Self {
        var report = ov_report(); report.status = status
        return Self(status: status, output: Data(), report: VisionReport(report))
    }
}

// Single-use owner. All session pointer accesses are under lock except ov_run on
// its serial queue. Destruction is queued AFTER run and performed under lock,
// excluding independent cancellation. No pointer escapes to the caller.
final class VisionWorker: @unchecked Sendable {
    enum Failure: Error { case allocation }
    private enum State { case idle, reserved, finished, closing, closed }
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "app.orivyn.proof.vision", qos: .userInitiated)
    private var session: OpaquePointer?
    private var state = State.idle
    init() throws {
        guard let pointer = ov_create() else { throw Failure.allocation }
        session = pointer
    }
    var isRunning: Bool { lock.withLock { state == .reserved } }
    var isClosed: Bool { lock.withLock { state == .closed } }
    func cancel() { lock.withLock { if let session { ov_cancel(session) } } }
    func run(image: OwnedRGB, question: String, model: String, projector: String) async -> VisionResult {
        // Enqueue inside the reservation lock so close cannot overtake admission.
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    guard state == .idle else { continuation.resume(returning: .rejected(7)); return }
                    state = .reserved
                    queue.async { [self] in
                        let result = execute(image: image, question: question, model: model, projector: projector)
                        lock.withLock { if state == .reserved { state = .finished } }
                        continuation.resume(returning: result)
                    }
                }
            }
        } onCancel: { self.cancel() }
    }
    private func execute(image: OwnedRGB, question: String, model: String, projector: String) -> VisionResult {
        guard let pointer = lock.withLock({ session }) else { return .rejected(7) }
        guard image.width > 0, image.height > 0, image.width <= 512, image.height <= 512,
              image.bytes.count == image.width * image.height * 3,
              !model.contains("\0"), !projector.contains("\0") else { return .rejected(1) }
        var output = [CChar](repeating: 0, count: 16384)
        var report = ov_report()
        let questionBytes = question.utf8.count
        let status = model.withCString { modelPtr in
            projector.withCString { projectorPtr in
                question.withCString { questionPtr in
                    image.bytes.withUnsafeBytes { rgb in
                        var request = ov_request(model: modelPtr, projector: projectorPtr,
                            rgb: rgb.baseAddress!.assumingMemoryBound(to: UInt8.self), rgb_bytes: rgb.count,
                            width: UInt32(image.width), height: UInt32(image.height), question: questionPtr,
                            question_bytes: questionBytes, context: 2048, output_tokens: 128)
                        return ov_run(pointer, &request, &output, 16384, &report)
                    }
                }
            }
        }
        let bytes = output.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return VisionResult(status: status, output: Data(bytes), report: VisionReport(report))
    }
    func close() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.withLock {
                state = .closing
                if let session { ov_cancel(session) }
                queue.async { [self] in
                    lock.withLock {
                        if let session { ov_destroy(session); self.session = nil }
                        state = .closed
                    }
                    continuation.resume()
                }
            }
        }
    }
    deinit {
        // Queue work retains self until run/close completes, so no computation can
        // still use this handle when last owner releases without explicit close.
        if let session { ov_destroy(session) }
    }
}
