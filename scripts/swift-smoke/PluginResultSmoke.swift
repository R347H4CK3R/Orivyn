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
actor ResultClient: PluginMCPClient {
    var calls = 0
    let fail: Bool
    init(fail: Bool = false) { self.fail = fail }
    func initialize() async throws -> MCPServerInfo { .init(name: "Synthetic", version: "1") }
    func listTools() async throws -> [MCPToolDefinition] {
        [.init(name: "fixture.read", inputSchema: try MCPToolSchema(json: .object(["type": .string("object")]))) ]
    }
    func callTool(named: String, arguments: MCPJSONValue) async throws -> MCPToolCallResult {
        calls += 1
        if fail { throw MCPClientFailure(.timedOut, effectMayHaveOccurred: true) }
        return .init(content: [.text("synthetic result")], structuredContent: nil, isError: false)
    }
    func cancelCurrentOperation() async {}
    func close() async {}
}
@main struct PluginResultSmoke {
    @MainActor static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Plugin result check failed: \(error)\n".utf8)); exit(1) }
    }
    @MainActor static func run() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("records")
        let client = ResultClient(), context = UUID()
        let broker = try PluginBroker(directory: root, clientFactory: { _,_ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let review = try broker.prepareReview(toolName: "fixture.read", argumentText: "{}")
        guard broker.completedResult == nil else { throw Probe.failure("Review exposed an unexecuted result") }
        try await broker.execute(reviewID: review.id, conversationContext: context)
        guard let result = broker.completedResult else { throw Probe.failure("No completed receipt") }
        func rejected(_ body: () throws -> Void) throws {
            do { try body() } catch { return }
            throw Probe.failure("Expected rejection")
        }
        try rejected { _ = try broker.consumeResultDraft(executionID: result.executionID, conversationContext: UUID(), currentDraft: "keep") }
        try rejected { _ = try broker.consumeResultDraft(executionID: UUID(), conversationContext: context, currentDraft: "keep") }
        try rejected { _ = try broker.consumeResultDraft(executionID: result.executionID, conversationContext: context, currentDraft: String(repeating: "x", count: 32_768)) }
        guard broker.completedResult != nil else { throw Probe.failure("Rejection consumed the result") }
        let text = try broker.consumeResultDraft(executionID: result.executionID, conversationContext: context, currentDraft: "keep")
        guard text.hasPrefix("keep\n\n"), text.contains("synthetic result"), text.contains("not independently verified") else { throw Probe.failure("Incorrect draft") }
        try rejected { _ = try broker.consumeResultDraft(executionID: result.executionID, conversationContext: context, currentDraft: text) }
        guard await client.calls == 1 else { throw Probe.failure("Handoff dispatched another call") }
        print("PASS completed result, context/result binding, bounds, append and replay rejection")
        let next = try broker.prepareReview(toolName: "fixture.read", argumentText: "{}")
        try await broker.execute(reviewID: next.id, conversationContext: context)
        broker.disconnect()
        guard broker.completedResult == nil, try PluginBroker(directory: root).completedResult == nil else { throw Probe.failure("Disconnect/relaunch retained result") }
        let failure = ResultClient(fail: true)
        let failed = try PluginBroker(directory: root.appendingPathComponent("failure"), clientFactory: { _,_ in failure })
        try await failed.connect(endpointText: "https://example.invalid/mcp", token: "")
        try failed.installConnection(rememberToken: false)
        let request = try failed.prepareReview(toolName: "fixture.read", argumentText: "{}")
        do { try await failed.execute(reviewID: request.id, conversationContext: context); throw Probe.failure("Expected failure") }
        catch is MCPClientFailure {}
        guard failed.completedResult == nil else { throw Probe.failure("Unknown result became consumable") }
        print("PASS disconnect, relaunch and unknown outcomes have no handoff")
    }
}
