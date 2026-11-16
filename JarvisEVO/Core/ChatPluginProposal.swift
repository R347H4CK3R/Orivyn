import Foundation

/// In-memory suggestion, never an approval or a replayable instruction.
struct PendingChatPluginProposal: Identifiable, Sendable {
    let id: UUID
    let proposal: PluginToolProposal
    let request: PluginChatRequest
    let assistantID: UUID
    let generationID: UUID
    let createdAt: Date

    func isCurrent(conversation: UUID, provider: UUID, connection: UUID?, catalog: UUID,
                   generation: UUID?, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        return age.isFinite && age >= 0 && age <= 300 && generationID == generation
            && request.matches(conversation: conversation, provider: provider, connection: connection, catalog: catalog)
    }
}
struct ChatPluginReviewRoute: Identifiable, Sendable {
    let id: UUID
    let tool: MCPToolDefinition
    let arguments: MCPJSONValue
    let request: PluginChatRequest
}

enum ChatPluginCatalog {
    static func validate(_ tools: [MCPToolDefinition], goal: String) throws {
        // Byte-exact uniqueness avoids a model selecting an ambiguous schema.
        let names = tools.map { Data($0.name.utf8) }
        guard Set(names).count == names.count else { throw MCPClientFailure(.unknownTool) }
        _ = try PluginToolProposal.prompt(goal: goal, tools: tools)
    }
}

/// Caller must bind a concrete on-device provider. This adapter has no network,
/// broker or execution capability. A valid proposal only pauses for human review.
struct ChatPluginProposalProvider: AIProvider {
    let id = "chat-plugin-proposal"
    let displayName = "On-device connected-tool proposal"
    let goal: String
    let tools: [MCPToolDefinition]
    let model: any AIProvider
    let makeFallback: @Sendable () -> any AIProvider
    let validateContext: @Sendable () async throws -> Void
    let publish: @Sendable (PluginToolProposal) async throws -> Void

    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        try ChatPluginCatalog.validate(tools, goal: goal)
        try Task.checkCancellation()
        try await validateContext()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let proposal = try await withThrowingTaskGroup(of: PluginToolProposal?.self) { group in
                        group.addTask { try await PluginToolProposal.generate(goal: goal, tools: tools, provider: model) }
                        group.addTask { try await Task.sleep(for: .seconds(120)); throw NormalChatLoopError.deadline }
                        defer { group.cancelAll() }
                        return try await group.next()!
                    }
                    try Task.checkCancellation()
                    try await validateContext()
                    if let proposal {
                        try await publish(proposal)
                        try Task.checkCancellation()
                        try await validateContext()
                        continuation.yield("A connected-tool call is suggested, not executed. Review the exact destination and arguments in the suggested-call card before running it.")
                    } else {
                        for try await token in try await makeFallback().stream(request) {
                            try Task.checkCancellation()
                            try await validateContext()
                            continuation.yield(token)
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
