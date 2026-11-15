import Foundation

struct VisionModelArtifact: Sendable, Equatable {
    let name: String
    let bytes: Int64
    let sha256: String
    var url: URL { URL(string: "https://huggingface.co/\(VisionModelPair.repository)/resolve/\(VisionModelPair.revision)/\(name)")! }
}
enum VisionModelPair {
    static let displayName = "LFM2.5-VL 1.6B"
    static let license = "LFM Open License 1.0"
    static let licenseResource = "LFM-Vision-LICENSE"
    static let repository = "LiquidAI/LFM2.5-VL-1.6B-GGUF"
    static let revision = "36fc16bc95133424921bcc3da009e83b2f23ffb5"
    static let model = VisionModelArtifact(name: "LFM2.5-VL-1.6B-Q6_K.gguf", bytes: 962_844_544,
        sha256: "5436b6e50a2d0c8c3b1f3b4c5f37fd8d75512e56590a55f5a989ad40170a8c37")
    static let projector = VisionModelArtifact(name: "mmproj-LFM2.5-VL-1.6b-F16.gguf", bytes: 853_993_856,
        sha256: "2cddba98b98390c011c606c416de2e63dcfdd3b21452bf71ad6aab59fa52d2ee")
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
