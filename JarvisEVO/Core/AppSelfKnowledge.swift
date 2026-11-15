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
        Bundled capability knowledge schema \(value.schemaVersion). Repository: \(value.repository); visibility is not checked.
        Metadata is not permission or proof of actions. Settings > Inspect private source requires explicit authorization. Chat cannot inspect source or modify this executable. self-repair [notAvailable]: cannot build or publish fixes. Desk uses app panels; experimental VM remains unverified on iPhone. Chat has no visual understanding. Draft bug reports with redacted evidence; never claim a fix without tests.
        """
    }
}
