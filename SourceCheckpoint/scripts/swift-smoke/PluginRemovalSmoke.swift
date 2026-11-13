import Foundation

// Only Keychain and network are replaced. Broker, journal and removal helper are exact production sources.
@MainActor struct PluginCredentialStore {
    static var token: String?
    static func read(endpoint: String) throws -> String? { token }
    static func save(_ value: String?, endpoint: String) throws { token = value }
}
actor MCPHTTPClient {
    init(endpoint: MCPEndpoint, bearerToken: String?) throws { }
    func initialize() async throws -> MCPServerInfo { throw Probe.failure("Unexpected network access") }
    func listTools() async throws -> [MCPToolDefinition] { throw Probe.failure("Unexpected network access") }
    func callTool(named: String, arguments: MCPJSONValue) async throws -> MCPToolCallResult { throw Probe.failure("Unexpected network access") }
    func cancelCurrentOperation() async { }
    func close() async { }
}
enum Probe: Error { case failure(String) }
@main struct PluginRemovalSmoke {
    @MainActor static func main() {
        do { try run() }
        catch { FileHandle.standardError.write(Data("Plugin removal check failed: \(error)\n".utf8)); exit(1) }
    }
    @MainActor static func run() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("records")
        let endpoint = "https://example.invalid/mcp"
        let id = UUID()
        let record = PluginConnectionRecord(id: id, endpoint: endpoint, name: "Fixture", version: "1", installedAt: Date(), hasSavedToken: true)
        struct Saved: Encodable { let version = 1; let connections: [PluginConnectionRecord] }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("plugin-connections.json")
        let original = try JSONEncoder().encode(Saved(connections: [record]))
        try original.write(to: file)
        PluginCredentialStore.token = "synthetic-test-token"
        let broker = try PluginBroker(directory: root)
        let preserved = root.appendingPathComponent("preserved.json")
        try FileManager.default.moveItem(at: file, to: preserved)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        var rejected = false
        do { try broker.removeConnection(id: id) } catch { rejected = true }
        guard rejected, broker.connections == [record], PluginCredentialStore.token == "synthetic-test-token",
              try Data(contentsOf: preserved) == original else { throw Probe.failure("Failed metadata save lost existing connection or credential") }
        print("PASS metadata write failure preserves credential and connection")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: preserved, to: file)
        try broker.removeConnection(id: id)
        guard broker.connections.isEmpty, PluginCredentialStore.token == nil,
              try PluginBroker(directory: root).connections.isEmpty else { throw Probe.failure("Removal did not persist") }
        print("PASS successful removal clears credential and persisted metadata")
    }
}
