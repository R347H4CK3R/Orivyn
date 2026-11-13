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

// Keep catalog-only guidance out of persistent installed model manifests.
struct LocalModelCatalogEntry: Identifiable, Sendable {
    let descriptor: LocalModelDescriptor
    let baseModel: String
    let family: String
    let purpose: String
    let quantization: String
    let recommendedRAMGB: Int
    let notes: String
    let licenseURL: URL?
    var id: String { descriptor.id }
    var requiredFreeStorageBytes: Int64 { descriptor.byteCount * 2 + 100_000_000 }
    var formattedFreeStorage: String { ByteCountFormatter.string(fromByteCount: requiredFreeStorageBytes, countStyle: .file) }
    func meetsRAMGuidance(physicalMemory: UInt64) -> Bool {
        physicalMemory >= UInt64(recommendedRAMGB) * 1_000_000_000
    }
}
enum LocalModelCatalog {
    static var defaultModel: LocalModelDescriptor { entries.first { $0.id == defaultModelID }!.descriptor }
    static var recommended: [LocalModelDescriptor] { entries.map(\.descriptor) }
    static let purposes = ["All", "General chat", "Coding", "Reasoning"]
    static func filtered(query: String, purpose: String, smallestFirst: Bool) -> [LocalModelCatalogEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = entries.filter { entry in
            (purpose == "All" || entry.purpose == purpose) &&
            (query.isEmpty || [entry.descriptor.name, entry.baseModel, entry.family, entry.purpose, entry.quantization]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
        if smallestFirst {
            return matches.sorted {
                $0.descriptor.byteCount == $1.descriptor.byteCount ? $0.id < $1.id : $0.descriptor.byteCount < $1.descriptor.byteCount
            }
        }
        return matches
    }
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
    case generationLimitReached
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
        case .generationLimitReached: "The local reply reached its token limit before finishing. Any partial response is kept but is incomplete. Ask for a shorter answer or split the request."
        case .emptyGeneration: "The model ended without producing a reply. Try rephrasing your message."
        }
    }
}
