import Foundation

/// Native adapter for the lifecycle owner. This proof host supplies an immutable,
/// hash-verified model directory. Production must use the verified pair store;
/// arbitrary paths are not a production installation or admission boundary.
final class SessionVisionRuntime: LocalVisionRuntime {
    enum Failure: Error { case native(Int32), invalidOutput }
    private let worker: VisionWorker
    private let model: String
    private let projector: String
    init(model: String, projector: String) throws {
        self.model = model; self.projector = projector
        worker = try VisionWorker()
    }
    func run(encodedImage: Data, question: String) async throws -> String {
        try Task.checkCancellation()
        // This nonisolated async method decodes away from the main actor. The
        // boundary creates only a bounded oriented thumbnail from owned bytes.
        let image = try ImageBoundary.decode(encodedImage)
        try Task.checkCancellation()
        let result = await worker.run(image: image, question: question, model: model, projector: projector)
        guard result.status == 0 else { throw Failure.native(result.status) }
        guard let answer = result.text, !answer.isEmpty else { throw Failure.invalidOutput }
        return answer
    }
    func cancel() { worker.cancel() }
    func close() async -> Bool { await worker.close(); return worker.isClosed }
}
