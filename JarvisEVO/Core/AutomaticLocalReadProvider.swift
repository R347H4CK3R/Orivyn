import Foundation

/// A deterministic answer adapter for an explicitly requested local read.
/// Ignores model context; never sends evidence or prompts to another provider.
struct AutomaticLocalReadProvider: AIProvider {
    let id = "automatic-local-read"
    let displayName = "Local read"
    let toolName: String
    let read: @Sendable () async throws -> String

    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        try Task.checkCancellation()
        let evidence = try await read()
        try Task.checkCancellation()
        guard evidence.utf8.count <= 4096 else { throw LocalAgentError.invalidState }
        // JSON evidence is intentionally not interpreted as an instruction or an
        // independently verified remote effect. Inert text preserves caveats.
        let result = "Completed local read: \(toolName). No model or remote service was used.\n\n" + evidence
        return AsyncThrowingStream { continuation in
            continuation.yield(result)
            continuation.finish()
        }
    }
}

/// Strict current-composer contract only. Each iterator advance performs exactly
/// one requested read, so successful prior evidence survives a later failure.
/// No producer task can continue executing after the consumer stops.
struct AutomaticLocalReadPlanProvider: AIProvider {
    let id = "automatic-local-read-plan"
    let displayName = "Local reads"
    let contract: LocalCompletionContract
    let read: @Sendable (LocalCompletionContract.Action) async throws -> String

    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        try Task.checkCancellation()
        let cursor = LocalReadPlanCursor(contract: contract, read: read)
        return AsyncThrowingStream(unfolding: { try await cursor.next() })
    }
}

private actor LocalReadPlanCursor {
    let contract: LocalCompletionContract
    let read: @Sendable (LocalCompletionContract.Action) async throws -> String
    private var index = 0
    private var evidenceBytes = 0
    private var stopped = false

    init(contract: LocalCompletionContract, read: @escaping @Sendable (LocalCompletionContract.Action) async throws -> String) {
        self.contract = contract; self.read = read
    }

    func next() async throws -> String? {
        try Task.checkCancellation()
        guard !stopped, index < contract.steps.count else { return nil }
        // Prevent reentrant consumers from executing a second read concurrently.
        stopped = true
        let action = contract.steps[index]
        let evidence = try await read(action)
        try Task.checkCancellation()
        guard evidence.utf8.count <= 4096,
              evidenceBytes + evidence.utf8.count <= 12_288 else { throw LocalAgentError.invalidState }
        evidenceBytes += evidence.utf8.count
        index += 1
        stopped = false
        var result = "Completed local read \(index)/\(contract.steps.count): \(action.name). No model or remote service was used.\n\n" + evidence + "\n\n"
        if index == contract.steps.count { result += "Completed all \(index) requested local reads." }
        return result
    }
}
