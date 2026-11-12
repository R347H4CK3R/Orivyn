import Foundation

struct LocalAIProvider: AIProvider {
    let store: LocalModelStore
    let model: LocalModelDescriptor
    private let engine = LlamaEngine()
    var id: String { "local:\(model.id)" }
    var displayName: String { "On-device · \(model.name)" }

    init(store: LocalModelStore, model: LocalModelDescriptor = LocalModelCatalog.defaultModel) {
        self.store = store
        self.model = model
    }

    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        // This actor verifies bytes locally. Inference itself performs no network calls.
        let url = try await store.verifiedURL(for: model)
        try Task.checkCancellation()
        return try await engine.stream(request, modelURL: url)
    }

    func unload() async { await engine.unload() }
}
