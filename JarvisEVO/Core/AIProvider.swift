import Foundation

struct GenerationRequest: Sendable {
    let messages: [ChatMessage]
    let systemPrompt: String
    var maxTokens: Int = 512
    var temperature: Float = 0.7
    /// Internal local-agent mode only; nil preserves normal chat sampling.
    var localAgentRequiresTool: Bool? = nil
    /// Opt-in Qwen3 non-thinking template mode; ignored by other architectures.
    var conciseQwen3: Bool = false
}

protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error>
}
