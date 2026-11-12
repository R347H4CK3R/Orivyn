import Foundation

struct GenerationRequest: Sendable {
    let messages: [ChatMessage]
    let systemPrompt: String
    var maxTokens: Int = 512
    var temperature: Float = 0.7
}

protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error>
}

enum ProviderError: LocalizedError {
    case notConfigured, invalidEndpoint, invalidModel, invalidResponse, server(Int), rejected(String), emptyResponse
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Install a local model or configure an endpoint to start."
        case .invalidEndpoint: "Use an HTTPS endpoint without credentials, query parameters or a fragment."
        case .invalidModel: "Enter the model name provided by your endpoint."
        case .invalidResponse: "The provider sent an invalid response."
        case .server(let code): "The endpoint returned HTTP \(code). Check its address, model, credentials and usage limits."
        case .rejected(let text): text
        case .emptyResponse: "The model returned no text. Try a shorter prompt or another model."
        }
    }
}
