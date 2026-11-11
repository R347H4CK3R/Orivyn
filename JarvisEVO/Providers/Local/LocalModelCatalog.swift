import Foundation

struct LocalModelDescriptor: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let fileName: String
    let downloadURL: URL?
    let sha256: String
    let byteCount: Int64
    let license: String
    let sourceURL: URL?

    var formattedSize: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
}

enum LocalModelCatalog {
    // Official Qwen artifact. Both URL revision and expected content digest are pinned.
    static let defaultModel = LocalModelDescriptor(
        id: "qwen2.5-0.5b-instruct-q4_k_m",
        name: "Qwen 2.5 · 0.5B · Q4_K_M",
        fileName: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
        downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/9217f5db79a29953eb74d5343926648285ec7e67/qwen2.5-0.5b-instruct-q4_k_m.gguf"),
        sha256: "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db",
        byteCount: 491_400_032,
        license: "Apache-2.0",
        sourceURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF")
    )
    static let recommended = [defaultModel]
}

enum LocalModelError: LocalizedError, Equatable {
    case invalidDescriptor
    case invalidGGUF
    case notInstalled
    case integrityMismatch
    case insufficientStorage
    case tooLarge
    case downloadFailed(Int)
    case insecureURL
    case busy
    case loadFailed
    case missingChatTemplate
    case unsupportedChatTemplate
    case promptTooLong
    case invalidRequest
    case decodingFailed(Int32)
    case emptyGeneration

    var errorDescription: String? {
        switch self {
        case .invalidDescriptor: "The model record contains an invalid file name, size, or checksum."
        case .invalidGGUF: "This file is not a supported GGUF v2/v3 model."
        case .notInstalled: "Download or import the selected local model first."
        case .integrityMismatch: "The model failed its integrity check. Remove it and download or import a fresh copy."
        case .insufficientStorage: "There is not enough free storage to safely install this model."
        case .tooLarge: "This first version supports GGUF files up to 2 GB to limit memory pressure on iPhone."
        case .downloadFailed(let status): "Model download failed (HTTP \(status)). No model was installed."
        case .insecureURL: "Models must be downloaded over HTTPS."
        case .busy: "A local model operation is already running. Stop it before starting another."
        case .loadFailed: "The model could not load. It may be unsupported or exceed available device memory."
        case .missingChatTemplate: "This GGUF has no chat template. Import an instruction model with an embedded chat template."
        case .unsupportedChatTemplate: "This model's chat template is not supported by the bundled runtime."
        case .promptTooLong: "This conversation exceeds the local model's 2,048-token working limit. Start a new conversation or shorten your message."
        case .invalidRequest: "The generation settings or message are not valid."
        case .decodingFailed(let code): "Local inference stopped with runtime code \(code). Try a smaller model or a shorter conversation."
        case .emptyGeneration: "The model ended without producing a reply. Try rephrasing your message."
        }
    }
}
