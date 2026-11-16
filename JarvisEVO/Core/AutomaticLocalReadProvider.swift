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
