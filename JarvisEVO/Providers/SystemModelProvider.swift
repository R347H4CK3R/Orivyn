import Foundation
import FoundationModels

/// Optional system model; availability is not assumed and is separate from open-weight model support.
struct SystemModelProvider: AIProvider {
    let id = "apple-system"
    let displayName = "Apple on-device model"
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This device is not eligible for Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Enable Apple Intelligence in iPhone Settings to use this optional model."
        case .unavailable(.modelNotReady): "The system model is not ready. Check Apple Intelligence downloads."
        case .unavailable: "The system model is currently unavailable."
        }
    }
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        if let reason = Self.unavailableReason { throw ProviderError.rejected(reason) }
        let context = try ContextWindow.trim(request.messages, characterBudget: 9_000 - request.systemPrompt.count)
        guard context.contains(where: { $0.role == .user }) else { throw ConversationError.tooLarge }
        let prompt = context.map { "\($0.role.rawValue): \($0.promptContent)" }.joined(separator: "\n\n")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: request.systemPrompt)
                    let options = GenerationOptions(temperature: Double(max(0, min(request.temperature, 1))), maximumResponseTokens: min(request.maxTokens, 1_024))
                    let stream = session.streamResponse(to: prompt, options: options)
                    var previous = ""
                    for try await snapshot in stream {
                        try Task.checkCancellation()
                        let output = snapshot.content
                        // Appends may extend the previous grapheme (accent, emoji, or CRLF).
                        // Compare and slice UTF-8, not Character boundaries; reject real rewrites.
                        guard output.utf8.starts(with: previous.utf8) else { throw ProviderError.invalidResponse }
                        let token = String(decoding: output.utf8.dropFirst(previous.utf8.count), as: UTF8.self)
                        if !token.isEmpty { continuation.yield(token) }
                        previous = output
                    }
                    guard !previous.isEmpty else { throw ProviderError.emptyResponse }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
