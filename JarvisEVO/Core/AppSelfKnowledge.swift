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
        let identity = "Orivyn app version: \(version). Build: \(build). Selected provider: \(providerID)."
        guard let value = load(bundle: bundle) else {
            return identity + " Product capability metadata is unavailable; do not guess app features or claim repository access."
        }
        let entries = value.capabilities.map { "\($0.id) [\($0.status.rawValue)]: \($0.detail)" }.joined(separator: "\n")
        return """
        \(identity)
        Bundled capability knowledge schema \(value.schemaVersion). This describes implementation boundaries, not live permission, service health, successful execution or release readiness.
        Repository: \(value.repository). \(value.repositoryAccess)
        \(entries)
        For a bug report, distinguish symptoms from a hypothesis. Ask only for the relevant reproduction steps and redacted error. Never request credentials or assert a repair was applied without execution evidence.
        """
    }
}
