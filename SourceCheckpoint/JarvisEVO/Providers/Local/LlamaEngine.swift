import Foundation
import llama

/// A single actor owns llama's mutable context. No runtime pointer leaves this file.
/// Different replies never share a KV cache, so cancelled output cannot leak into the
/// next request. The caller supplies the complete, visible conversation each time.
actor LlamaEngine: LocalResourceReleasing {
    private static let backend: Void = { llama_backend_init() }()
    private let contextSize: UInt32 = 2048
    private let batchSize = 128
    private var resources: LlamaResources?
    private var loadedPath: String?
    private var busy = false
    private var workerTask: Task<Void, Never>?
    private var releaseRequests = 0

    func stream(_ request: GenerationRequest, modelURL: URL) throws -> AsyncThrowingStream<String, Error> {
        guard !busy, releaseRequests == 0 else { throw LocalModelError.busy }
        guard (1...1024).contains(request.maxTokens), request.temperature.isFinite,
              (0...2).contains(request.temperature), request.messages.contains(where: { $0.role == .user && (!$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.attachments.contains(where: { !($0.extractedText ?? "").isEmpty })) }),
              request.systemPrompt.utf8.count + request.messages.reduce(0, { $0 + $1.content.utf8.count }) <= 1_000_000 else { throw LocalModelError.invalidRequest }
        busy = true
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        let worker = Task {
            do {
                try await generate(request, modelURL: modelURL, continuation: pair.continuation)
                pair.continuation.finish()
            } catch {
                pair.continuation.finish(throwing: error)
            }
            busy = false
            workerTask = nil
        }
        workerTask = worker
        pair.continuation.onTermination = { @Sendable _ in worker.cancel() }
        return pair.stream
    }

    /// Cancellation is cooperative at decode boundaries. Awaiting this method,
    /// unlike merely canceling a consumer, is a real resource-release barrier.
    func unload() async {
        releaseRequests += 1
        defer { releaseRequests -= 1 }
        let worker = workerTask
        worker?.cancel()
        await worker?.value
        // generate() has returned, so its local owner/sampler/KV references are gone.
        // Concurrent releasers keep admission closed until every waiter resumes.
        resources = nil
        loadedPath = nil
    }

    private func load(_ url: URL) throws -> LlamaResources {
        if let resources, loadedPath == url.path { return resources }
        resources = nil
        loadedPath = nil
        _ = Self.backend
        var modelParameters = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParameters.n_gpu_layers = 0
        #else
        modelParameters.n_gpu_layers = 99
        #endif
        modelParameters.use_mmap = true
        guard let model = url.path.withCString({ llama_model_load_from_file($0, modelParameters) }) else { throw LocalModelError.loadFailed }
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = contextSize
        contextParameters.n_batch = UInt32(batchSize)
        contextParameters.n_ubatch = UInt32(batchSize)
        contextParameters.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
        contextParameters.n_threads_batch = contextParameters.n_threads
        #if targetEnvironment(simulator)
        contextParameters.offload_kqv = false
        #endif
        guard let context = llama_init_from_model(model, contextParameters) else {
            llama_model_free(model)
            throw LocalModelError.loadFailed
        }
        let loaded = LlamaResources(model: model, context: context)
        resources = loaded
        loadedPath = url.path
        return loaded
    }

    private func generate(_ request: GenerationRequest, modelURL: URL, continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        try Task.checkCancellation()
        let owned = try load(modelURL)
        let model = owned.model
        let context = owned.context
        guard let vocabulary = llama_model_get_vocab(model) else { throw LocalModelError.loadFailed }
        llama_memory_clear(llama_get_memory(context), true)
        defer { llama_memory_clear(llama_get_memory(context), true) }
        // Capture the resource owner, not task-local raw-pointer aliases. The
        // synchronous callback obtains its pointers within this actor's isolation.
        try LocalPromptBuilder.validateSystemPrompt(request.systemPrompt, maxTokens: request.maxTokens, contextSize: Int(contextSize)) { [owned] text in
            guard let promptVocabulary = llama_model_get_vocab(owned.model) else { throw LocalModelError.loadFailed }
            return try tokenCount(text, vocabulary: promptVocabulary)
        }
        let messages = try LocalPromptBuilder.trimToFit(LocalPromptBuilder.messages(from: request.messages), maxTokens: request.maxTokens, contextSize: Int(contextSize)) { [owned] entries in
            guard let promptVocabulary = llama_model_get_vocab(owned.model) else { throw LocalModelError.loadFailed }
            let rendered = try format(entries, systemPrompt: request.systemPrompt, model: owned.model)
            return try tokenCount(rendered, vocabulary: promptVocabulary)
        }
        let prompt = try format(messages, systemPrompt: request.systemPrompt, model: model)
        let tokens = try tokenize(prompt, vocabulary: vocabulary)
        guard !tokens.isEmpty, tokens.count + request.maxTokens <= Int(contextSize) else { throw LocalModelError.promptTooLong }

        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else { throw LocalModelError.loadFailed }
        defer { llama_sampler_free(sampler) }
        if let requireTool = request.localAgentRequiresTool {
            let grammar = try LocalAgentGrammar.load(requireTool: requireTool)
            let constrained = grammar.withCString { specification in
                "root".withCString { name in llama_sampler_init_grammar(vocabulary, specification, name) }
            }
            guard let constrained else { throw LocalModelError.loadFailed }
            llama_sampler_chain_add(sampler, constrained)
        }
        if request.temperature == 0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(request.temperature))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: UInt32.min...UInt32.max)))
        }
        for offset in stride(from: 0, to: tokens.count, by: batchSize) {
            try Task.checkCancellation()
            var chunk = Array(tokens[offset..<min(offset + batchSize, tokens.count)])
            let result = chunk.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
            }
            guard result == 0 else { throw LocalModelError.decodingFailed(result) }
            await Task.yield()
        }
        var decoder = UTF8TokenAccumulator()
        var producedText = false
        var sawEndOfGeneration = false
        for _ in 0..<request.maxTokens {
            try Task.checkCancellation()
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocabulary, token) { sawEndOfGeneration = true; break }
            let bytes = try tokenBytes(token, vocabulary: vocabulary)
            if let text = decoder.append(bytes), !text.isEmpty {
                producedText = true
                if case .terminated = continuation.yield(text) { throw CancellationError() }
            }
            let result = withUnsafeMutablePointer(to: &token) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            guard result == 0 else { throw LocalModelError.decodingFailed(result) }
            await Task.yield()
        }
        try Task.checkCancellation()
        let suffix = decoder.finish()
        if !suffix.isEmpty { producedText = true; continuation.yield(suffix) }
        guard sawEndOfGeneration else { throw LocalModelError.generationLimitReached }
        guard producedText else { throw LocalModelError.emptyGeneration }
    }

    private func format(_ entries: [LocalPromptMessage], systemPrompt: String, model: OpaquePointer) throws -> String {
        guard let template = llama_model_chat_template(model, nil) else { throw LocalModelError.missingChatTemplate }
        var pairs: [(String, String)] = []
        if !systemPrompt.isEmpty { pairs.append(("system", systemPrompt)) }
        pairs += entries.map { ($0.role, $0.content) }
        var allocations: [UnsafeMutablePointer<CChar>] = []
        defer { allocations.forEach { $0.deallocate() } }
        func cString(_ text: String) -> UnsafePointer<CChar> {
            let bytes = text.replacingOccurrences(of: "\0", with: "�").utf8CString
            let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
            bytes.withUnsafeBufferPointer { source in
                pointer.initialize(from: source.baseAddress!, count: source.count)
            }
            allocations.append(pointer)
            return UnsafePointer(pointer)
        }
        let messages = pairs.map { llama_chat_message(role: cString($0.0), content: cString($0.1)) }
        let required = messages.withUnsafeBufferPointer { buffer in
            llama_chat_apply_template(template, buffer.baseAddress, buffer.count, true, nil, 0)
        }
        guard required > 0, required <= 2_000_000 else { throw LocalModelError.unsupportedChatTemplate }
        var output = [CChar](repeating: 0, count: Int(required) + 1)
        let outputCapacity = Int32(output.count)
        let written = messages.withUnsafeBufferPointer { buffer in
            llama_chat_apply_template(template, buffer.baseAddress, buffer.count, true, &output, outputCapacity)
        }
        guard written == required else { throw LocalModelError.unsupportedChatTemplate }
        return String(decoding: output.prefix(Int(written)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func tokenCount(_ text: String, vocabulary: OpaquePointer) throws -> Int {
        guard text.utf8.count <= 2_000_000 else { throw LocalModelError.promptTooLong }
        let count = text.withCString { llama_tokenize(vocabulary, $0, Int32(text.utf8.count), nil, 0, true, true) }
        guard count < 0, count != Int32.min else { throw LocalModelError.invalidRequest }
        return Int(-count)
    }

    private func tokenize(_ text: String, vocabulary: OpaquePointer) throws -> [llama_token] {
        let count = try tokenCount(text, vocabulary: vocabulary)
        guard count <= Int(contextSize) else { throw LocalModelError.promptTooLong }
        var tokens = [llama_token](repeating: 0, count: count)
        let written = text.withCString { llama_tokenize(vocabulary, $0, Int32(text.utf8.count), &tokens, Int32(count), true, true) }
        guard Int(written) == count else { throw LocalModelError.invalidRequest }
        return tokens
    }

    private func tokenBytes(_ token: llama_token, vocabulary: OpaquePointer) throws -> [UInt8] {
        var bytes = [CChar](repeating: 0, count: 256)
        var count = llama_token_to_piece(vocabulary, token, &bytes, 256, 0, false)
        if count < 0, count != Int32.min, -count <= 65536 {
            let required = -count
            bytes = [CChar](repeating: 0, count: Int(required))
            count = llama_token_to_piece(vocabulary, token, &bytes, required, 0, false)
        }
        guard count >= 0, Int(count) <= bytes.count else { throw LocalModelError.decodingFailed(count) }
        return bytes.prefix(Int(count)).map { UInt8(bitPattern: $0) }
    }
}

/// Actor-confined resource owner. Marked Sendable only to allow deterministic cleanup
/// in deinit under Swift 6; no pointer is exposed outside the owning LlamaEngine actor.
private final class LlamaResources: @unchecked Sendable {
    let model: OpaquePointer
    let context: OpaquePointer
    init(model: OpaquePointer, context: OpaquePointer) { self.model = model; self.context = context }
    deinit { llama_free(context); llama_model_free(model) }
}
