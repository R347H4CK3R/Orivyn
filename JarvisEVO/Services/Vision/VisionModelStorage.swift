import Foundation

/// Reuses the app's exact-size/SHA256-verified, bounded download and atomic file
/// installation, in a private root never listed as a text-model catalog.
struct VisionModelStorage: VisionPairFileStore {
    private let store: LocalModelStore
    init(root: URL) throws { store = try LocalModelStore(root: root) }
    private func descriptor(_ asset: VisionModelArtifact) -> LocalModelDescriptor {
        LocalModelDescriptor(id: asset.sha256, name: asset.name, fileName: asset.name,
            downloadURL: asset.url, sha256: asset.sha256, byteCount: asset.bytes,
            license: VisionModelPair.license, sourceURL: URL(string: "https://huggingface.co/\(VisionModelPair.repository)/tree/\(VisionModelPair.revision)"))
    }
    func verify(_ artifact: VisionModelArtifact) async throws -> URL {
        try await store.verifiedURL(for: descriptor(artifact))
    }
    func download(_ artifact: VisionModelArtifact, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await store.download(descriptor(artifact), policy: .userInitiated, progress: progress)
    }
}
@MainActor enum VisionServices {
    // A process-wide owner is required: separate sheets must not create separate
    // actors capable of replacing the same model while another worker uses it.
    static let store: Result<VisionPairStore, Error> = Result {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("JarvisEVO/VisionModels", isDirectory: true)
        return VisionPairStore(files: try VisionModelStorage(root: base))
    }
    static var nativeAvailable: Bool {
        #if ORIVYN_NATIVE_VISION
        true
        #else
        false
        #endif
    }
}
