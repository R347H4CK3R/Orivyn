import Foundation

/// Wi-Fi and wired mean confirmed non-expensive, non-constrained paths. Map
/// expensive Wi-Fi/hotspots to constrained. URLSession must also enforce policy.
enum AutomaticDownloadNetwork: Sendable, Equatable {
    case unknown, offline, wifi, wired, cellular, constrained
}

struct AutomaticRouteEnvironment: Sendable, Equatable {
    let physicalMemory: UInt64
    let freeStorageBytes: Int64?
    let network: AutomaticDownloadNetwork
    let allowsCellular: Bool
}

struct AutomaticModelDecision: Sendable, Equatable {
    let model: LocalModelDescriptor
    let needsDownload: Bool
    let reason: String
    let purpose: String
}

/// Local, deterministic preparation advice. This does not install, load, select,
/// submit, or grant permission. The coordinator must recheck ownership after awaits.
enum AutomaticModelRouter {
    static let textByteLimit = 32_768
    static let maximumDownloadBytes: Int64 = 1_200_000_000
    private static let minimumCodingBytes: Int64 = 1_117_320_768
    private static let minimumCodingRAM: UInt64 = 6_000_000_000

    static func route(text: String, installed: [LocalModelDescriptor], environment: AutomaticRouteEnvironment) throws -> AutomaticModelDecision {
        guard text.utf8.count <= textByteLimit else { throw AutomaticRoutingError.textTooLong }
        let coding = isCoding(text)
        let purpose = coding ? "Coding" : "General chat"
        // The 0.5B coder failed the native coding quality gate. Manual choices
        // remain available, but Automatic must not load it as an installed fallback.
        guard !coding || environment.physicalMemory >= minimumCodingRAM else {
            throw AutomaticRoutingError.insufficientMemory
        }
        let candidates = LocalModelCatalog.entries.filter { entry in
            entry.purpose == purpose && entry.meetsRAMGuidance(physicalMemory: environment.physicalMemory) &&
                (!coding || entry.descriptor.byteCount >= minimumCodingBytes)
        }
        let matching = candidates.filter { entry in
            installed.contains { installed in
                installed.id == entry.id && installed.sha256 == entry.descriptor.sha256 &&
                    installed.byteCount == entry.descriptor.byteCount && installed.fileName == entry.descriptor.fileName
            }
        }.sorted {
            $0.descriptor.byteCount == $1.descriptor.byteCount ? $0.id < $1.id : $0.descriptor.byteCount > $1.descriptor.byteCount
        }
        if let entry = matching.first {
            return AutomaticModelDecision(model: entry.descriptor, needsDownload: false,
                reason: "\(purpose) match: using the largest installed matching catalog model within this iPhone's RAM guidance. Files are verified again before inference; guidance does not guarantee available memory or answer quality.",
                purpose: purpose)
        }

        // Downloads are a narrower allowlist than installed-model selection. A
        // newly added catalog entry cannot silently become an automatic download.
        let targetID = coding ? "qwen2.5-coder-1.5b-instruct-q4_k_m" : "qwen2.5-0.5b-instruct-q4_k_m"
        let targetBytes: Int64 = coding ? minimumCodingBytes : 491_400_032
        guard let entry = LocalModelCatalog.entries.first(where: { $0.id == targetID }),
              entry.purpose == purpose, entry.descriptor.byteCount == targetBytes,
              entry.descriptor.byteCount <= maximumDownloadBytes,
              entry.descriptor.downloadURL != nil else { throw AutomaticRoutingError.catalogUnavailable }
        guard entry.meetsRAMGuidance(physicalMemory: environment.physicalMemory) else { throw AutomaticRoutingError.insufficientMemory }
        guard let free = environment.freeStorageBytes else { throw AutomaticRoutingError.storageUnknown }
        guard free >= entry.requiredFreeStorageBytes else { throw AutomaticRoutingError.insufficientStorage }
        switch environment.network {
        case .wifi, .wired: break
        case .cellular:
            guard environment.allowsCellular else { throw AutomaticRoutingError.cellularNotAllowed }
        case .constrained: throw AutomaticRoutingError.constrainedNetwork
        case .unknown: throw AutomaticRoutingError.networkUnknown
        case .offline: throw AutomaticRoutingError.offline
        }
        return AutomaticModelDecision(model: entry.descriptor, needsDownload: true,
            reason: "\(purpose) match: no compatible matching catalog model is installed. Prepare the pinned model (\(entry.descriptor.formattedSize)); it needs \(entry.formattedFreeStorage) free storage. Your draft stays unchanged until preparation succeeds.",
            purpose: purpose)
    }

    private static func isCoding(_ text: String) -> Bool {
        let text = text.lowercased()
        if text.contains("```") { return true }
        let tokens = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).map(String.init)
        let words = Set(tokens)
        let specific: Set<String> = ["debug", "debugging", "debugger", "refactor", "refactoring", "compiler", "compilation",
            "javascript", "typescript", "swiftui", "sql", "html", "css", "json", "regex", "traceback", "segfault"]
        if !words.isDisjoint(with: specific) { return true }
        let actions: Set<String> = ["write", "build", "create", "fix", "implement", "optimize", "compile", "explain", "test", "generate"]
        let codeObjects: Set<String> = ["code", "function", "script", "api", "algorithm"]
        guard !words.isDisjoint(with: actions) else { return false }
        if !words.isDisjoint(with: codeObjects) { return true }
        // A language name alone is ambiguous (Python the animal, Swift the bird,
        // Java the island). Require an adjacent language/artifact phrase and an action.
        // This is bounded lexical routing advice, not semantic intent detection.
        let languages: Set<String> = ["python", "swift", "rust", "java", "kotlin", "ruby",
            "golang", "csharp", "cpp", "scala", "php", "dart", "lua"]
        let programmingArtifacts: Set<String> = ["program", "programs", "class", "classes",
            "method", "methods", "parser", "parsers", "module", "modules", "tests"]
        for index in tokens.indices {
            if languages.contains(tokens[index]), index + 1 < tokens.count,
               programmingArtifacts.contains(tokens[index + 1]) { return true }
            if programmingArtifacts.contains(tokens[index]), index + 2 < tokens.count,
               tokens[index + 1] == "in", languages.contains(tokens[index + 2]) { return true }
        }
        return false
    }
}

enum AutomaticRoutingError: LocalizedError, Equatable {
    case textTooLong, catalogUnavailable, insufficientMemory, storageUnknown, insufficientStorage
    case networkUnknown, offline, cellularNotAllowed, constrainedNetwork

    var errorDescription: String? {
        switch self {
        case .textTooLong: "Automatic selection supports up to 32,768 UTF-8 bytes of typed text. Shorten the request or use Manual; your draft is unchanged."
        case .catalogUnavailable: "The approved model is unavailable in this catalog. Choose a model manually; nothing was downloaded."
        case .insufficientMemory: "This iPhone is below the catalog's RAM guidance for automatic models. Choose a compatible model manually; nothing was downloaded or loaded."
        case .storageUnknown: "Available storage could not be checked. Automatic download did not start; try again or select an installed model manually."
        case .insufficientStorage: "There is not enough free storage to install the matching model safely. Nothing was deleted. Choose an installed model or free space first."
        case .networkUnknown: "The connection has not been checked yet. Wait for Wi-Fi or Ethernet, or choose an installed model manually; your draft is unchanged."
        case .offline: "The matching model is not installed and this iPhone is offline. Connect to Wi-Fi or Ethernet, or choose an installed model manually."
        case .cellularNotAllowed: "Automatic downloads use Wi-Fi or Ethernet by default. Connect to one, explicitly allow cellular downloads, or choose an installed model."
        case .constrainedNetwork: "Automatic download is paused for a constrained or expensive connection. Use unrestricted Wi-Fi or Ethernet, or an installed model."
        }
    }
}
