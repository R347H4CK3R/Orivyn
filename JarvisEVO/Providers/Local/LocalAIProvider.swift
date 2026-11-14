import Foundation

struct LocalAIProvider: AIProvider {
    let store: LocalModelStore
    let model: LocalModelDescriptor
    let engine: LlamaEngine
    var id: String { "local:\(model.id)" }
    var displayName: String { "On-device · \(model.name)" }

    init(store: LocalModelStore, model: LocalModelDescriptor = LocalModelCatalog.defaultModel, engine: LlamaEngine = LlamaEngine()) {
        self.store = store
        self.model = model
        self.engine = engine
    }

    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        guard request.nativeReadGoal == nil || model.sha256 == NativeReadProposal.admittedModelSHA256 else { throw LocalModelError.invalidDescriptor }
        // This actor verifies bytes locally. Inference itself performs no network calls.
        let url = try await store.verifiedURL(for: model)
        try Task.checkCancellation()
        return try await engine.stream(request, modelURL: url)
    }

    #if ORIVYN_NATIVE_TOOLS
    func suggestNativeReads(goal: String, validateAdmission: @escaping @MainActor @Sendable () throws -> Void) async throws -> NativeReadProposal {
        guard model.sha256 == NativeReadProposal.admittedModelSHA256 else {
            throw ProviderError.rejected("Select the verified Qwen3 1.7B Q8_0 model for native read suggestions.")
        }
        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              goal.utf8.count <= 2048, !goal.contains("\0") else { throw LocalModelError.invalidRequest }
        var request = GenerationRequest(messages: [ChatMessage(role: .user, content: goal)], systemPrompt: "", maxTokens: 256, temperature: 0)
        request.nativeReadGoal = goal
        let url = try await store.verifiedURL(for: model)
        try await validateAdmission()
        try Task.checkCancellation()
        var output = ""
        for try await piece in try await engine.stream(request, modelURL: url) {
            try Task.checkCancellation()
            guard output.utf8.count + piece.utf8.count <= 4096 else { throw LocalAgentError.outputBound }
            output += piece
        }
        try Task.checkCancellation()
        return try NativeReadProposal.parse(output)
    }
    #endif

    func unload() async { await engine.unload() }
}
