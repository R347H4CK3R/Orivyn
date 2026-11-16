#if DEBUG
import Foundation
import SwiftUI

/// No network or inference: typed synthetic output still passes the production parser.
struct PluginPresentationFixtureModel: AIProvider {
    let id = "synthetic-plugin-presentation"
    let displayName = "Synthetic proposal, not inference"
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(#"{"tool":"fixture.search","arguments":{"query":"synthetic query"}}"#)
            continuation.finish()
        }
    }
}
actor PluginPresentationFixtureClient: PluginMCPClient {
    private(set) var calls = 0
    func initialize() async throws -> MCPServerInfo { .init(name: "Synthetic presentation only", version: "1") }
    func listTools() async throws -> [MCPToolDefinition] {
        [.init(name: "fixture.search", inputSchema: try MCPToolSchema(json: .object([
            "type": .string("object"), "properties": .object(["query": .object(["type": .string("string")])]),
            "required": .array([.string("query")]), "additionalProperties": .bool(false)])))]
    }
    func callTool(named: String, arguments: MCPJSONValue) async throws -> MCPToolCallResult {
        calls += 1
        throw CancellationError() // Never emulate a successful remote action.
    }
    func cancelCurrentOperation() async {}
    func close() async {}
}
struct PluginPresentationFixtureActions: Sendable {
    let change: @MainActor @Sendable (String) -> Void
}
private struct PluginPresentationFixtureActionsKey: EnvironmentKey {
    static let defaultValue: PluginPresentationFixtureActions? = nil
}
extension EnvironmentValues {
    var pluginPresentationFixtureActions: PluginPresentationFixtureActions? {
        get { self[PluginPresentationFixtureActionsKey.self] }
        set { self[PluginPresentationFixtureActionsKey.self] = newValue }
    }
}
#endif
