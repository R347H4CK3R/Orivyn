import Foundation

struct VisionModelArtifact: Sendable, Equatable {
    let name: String
    let bytes: Int64
    let sha256: String
    var url: URL { URL(string: "https://huggingface.co/\(VisionModelPair.repository)/resolve/\(VisionModelPair.revision)/\(name)")! }
}
enum VisionModelPair {
    static let repository = "ggml-org/SmolVLM2-2.2B-Instruct-GGUF"
    static let revision = "1bc3c9f74ceafd4c8d4411cc9cf188bba3798f91"
    static let model = VisionModelArtifact(name: "SmolVLM2-2.2B-Instruct-Q4_K_M.gguf", bytes: 1_112_602_656,
        sha256: "0cf76814555b8665149075b74ab6b5c1d428ea1d3d01c1918c12012e8d7c9f58")
    static let projector = VisionModelArtifact(name: "mmproj-SmolVLM2-2.2B-Instruct-f16.gguf", bytes: 872_303_680,
        sha256: "db9a3a1648cab1ebc3af4a2b0c8145dd8faebf6f7dd7b16e7dc1842229f14ac4")
    static let artifacts = [model, projector]
    static let totalBytes = model.bytes + projector.bytes
}

protocol VisionPairFileStore: Sendable {
    func verify(_ artifact: VisionModelArtifact) async throws -> URL
    func download(_ artifact: VisionModelArtifact, progress: @escaping @Sendable (Double) -> Void) async throws
}

/// One private pair store, separate from selectable text models. Verification of
/// both exact hashes precedes acquisition; no install can replace an active pair.
actor VisionPairStore {
    struct Lease: Sendable {
        let model: URL, projector: URL
        fileprivate let id: UUID
    }
    private let files: any VisionPairFileStore
    private var busy = false
    private var active: UUID?
    enum Failure: Error, LocalizedError {
        case busy
        var errorDescription: String? { "The vision model is in use or being prepared. Try again after it finishes." }
    }
    init(files: any VisionPairFileStore) { self.files = files }
    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !busy, active == nil else { throw Failure.busy }
        busy = true; defer { busy = false }
        var completed: Int64 = 0
        for artifact in VisionModelPair.artifacts {
            try Task.checkCancellation()
            let before = completed
            if (try? await files.verify(artifact)) == nil {
                try Task.checkCancellation()
                try await files.download(artifact) { value in
                    progress((Double(before) + Double(artifact.bytes) * value) / Double(VisionModelPair.totalBytes))
                }
            }
            _ = try await files.verify(artifact)
            completed += artifact.bytes
            progress(Double(completed) / Double(VisionModelPair.totalBytes))
        }
        try Task.checkCancellation()
    }
    func acquire() async throws -> Lease {
        try Task.checkCancellation()
        guard !busy, active == nil else { throw Failure.busy }
        busy = true; defer { busy = false }
        let model = try await files.verify(VisionModelPair.model)
        let projector = try await files.verify(VisionModelPair.projector)
        try Task.checkCancellation()
        let id = UUID(); active = id
        return Lease(model: model, projector: projector, id: id)
    }
    func release(_ lease: Lease) {
        if active == lease.id { active = nil }
    }
}
