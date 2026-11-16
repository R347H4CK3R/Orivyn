import Foundation

/// Bundled product metadata only. No source checkout, network reads or credentials.
struct AppSelfKnowledge: Decodable, Sendable {
    enum Status: String, Decodable, Sendable { case available, conditional, notAvailable }
    struct Capability: Decodable, Sendable {
        let id: String
        let status: Status
        let detail: String
    }
    let schemaVersion: Int
    let repository: String
    let repositoryAccess: String
    let capabilities: [Capability]

    static func decode(_ data: Data) -> Self? {
        guard data.count <= 12000, let value = try? JSONDecoder().decode(Self.self, from: data),
              value.schemaVersion == 1,
              value.repository == "https://github.com/R347H4CK3R/Orivyn",
              !value.repositoryAccess.isEmpty, !value.capabilities.isEmpty,
              value.capabilities.count <= 32,
              Set(value.capabilities.map(\.id)).count == value.capabilities.count,
              value.capabilities.allSatisfy({ !$0.id.isEmpty && !$0.detail.isEmpty }) else { return nil }
        return value
    }

    /// Product facts are data, not execution authority. Keep each prerequisite
    /// intact; budget pressure omits whole capabilities with explicit counts.
    static func toolResult(metadata: Self?, maximumBytes: Int = 4096) throws -> Data {
        let capabilities = metadata?.capabilities ?? []
        guard capabilities.count <= 24 else { throw LocalAgentError.outputBound }
        let items: [MCPJSONValue] = try capabilities.map { capability in
            guard !capability.id.isEmpty, capability.id.utf8.count <= 256,
                  !capability.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  capability.detail.utf8.count <= 1024,
                  !(capability.id + capability.detail).unicodeScalars.contains(where: {
                      $0.value < 32 && ![9, 10, 13].contains($0.value)
                  }) else { throw LocalAgentError.invalidState }
            return .object(["id": .string(capability.id), "status": .string(capability.status.rawValue),
                            "detail": .string(capability.detail)])
        }
        let result: MCPJSONValue = .object(["app": .string("Orivyn"), "assistant": .string("Jarvis"),
            "repository": .string("https://github.com/R347H4CK3R/Orivyn"),
            "repositoryAccess": .string("This tool reads bundled metadata, not repository source. A repository URL does not grant chat source access."),
            "capabilities": .array(items)])
        return try LocalToolResultBudget.encode(result, collection: "capabilities", maximumBytes: maximumBytes)
    }

    static func load(bundle: Bundle = .main) -> Self? {
        guard let url = bundle.url(forResource: "OrivynCapabilities", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func prompt(bundle: Bundle = .main, providerID: String) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return prompt(metadata: load(bundle: bundle), version: version, build: build, providerID: providerID)
    }

    static func prompt(metadata: Self?, version: String, build: String, providerID: String) -> String {
        let identity = "Orivyn app version: \(version). Build: \(build). Selected provider: \(providerID)."
        guard let value = metadata else {
            return identity + " Product capability metadata is unavailable; do not guess app features or claim repository access."
        }
        // Keep the full manifest locally; all local engines have a 2,048-token
        // context and reserve 1,024 output tokens. Do not inject every detail.
        return """
        \(identity)
        Bundled capability knowledge schema \(value.schemaVersion). Repository: \(value.repository).
        Metadata is not permission or proof of actions. Settings > Inspect private source requires explicit authorization. Chat cannot inspect source or modify this executable. self-repair [notAvailable]: cannot build or publish fixes. Desk uses app panels; experimental VM remains unverified on iPhone. Chat has no visual understanding. Draft bug reports with redacted evidence; never claim a fix without tests.
        """
    }
}
