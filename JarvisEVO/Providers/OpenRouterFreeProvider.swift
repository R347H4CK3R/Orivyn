import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A separate single-turn transport. Intentionally does not accept GenerationRequest,
/// messages, tools, attachments, memory or a configurable endpoint.
struct OpenRouterFreeProvider: Sendable {
    typealias Transport = @Sendable (URLRequest, Int) async throws -> (Data, HTTPURLResponse)
    static let catalogURL = URL(string: "https://openrouter.ai/api/v1/models")!
    static let completionURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let transport: Transport
    init() { transport = { try await FreeChatHTTP.perform($0, limit: $1) } }
    /// Internal dependency injection for synthetic test responses. No real key in tests.
    init(transport: @escaping Transport) { self.transport = transport }

    func fetchCatalog() async throws -> [OpenRouterFreeModel] {
        var request = URLRequest(url: Self.catalogURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        let data = try await send(request, limit: 4_194_304)
        return try Self.parseCatalog(data)
    }

    func complete(modelID: String, newlyAuthoredText: String, apiKey: String) async throws -> String {
        let result = try await completeTurn(manualModelID: modelID, newlyAuthoredText: newlyAuthoredText, apiKey: apiKey)
        return result.text
    }

    func completeAutomatically(newlyAuthoredText: String, apiKey: String) async throws -> FreeOnlineCompletion {
        try await completeTurn(manualModelID: nil, newlyAuthoredText: newlyAuthoredText, apiKey: apiKey)
    }

    private func completeTurn(manualModelID: String?, newlyAuthoredText: String, apiKey: String) async throws -> FreeOnlineCompletion {
        if let manualModelID, !Self.isConcreteFreeID(manualModelID) { throw OpenRouterFreeError.modelUnavailable }
        guard !apiKey.isEmpty, apiKey.utf8.count <= 512,
              apiKey.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw OpenRouterFreeError.keyRequired }
        guard !newlyAuthoredText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              newlyAuthoredText.utf8.count <= 24_000 else { throw OpenRouterFreeError.promptTooLong }
        try Task.checkCancellation()
        // Selection previews never authorize a request: verify the live price each time.
        let models = try await fetchCatalog()
        let model: OpenRouterFreeModel
        if let manualModelID {
            guard let selected = models.first(where: { $0.id == manualModelID }) else { throw OpenRouterFreeError.modelUnavailable }
            model = selected
        } else {
            model = try FreeOnlineAutoRouter.select(text: newlyAuthoredText, verifiedModels: models)
        }
        let modelID = model.id
        try Task.checkCancellation()
        var request = URLRequest(url: Self.completionURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        // Official provider-selection schema: prices per million tokens, plus per request.
        // Fixed concrete model + no provider fallback + independent zero-dollar ceilings.
        // https://openrouter.ai/docs/guides/routing/provider-selection#max-price
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID, "messages": [["role": "user", "content": newlyAuthoredText]],
            "stream": false, "max_tokens": 2_048,
            "provider": ["allow_fallbacks": false, "max_price": ["prompt": 0, "completion": 0, "request": 0]]
        ])
        let data = try await send(request, limit: 262_144)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["error"] == nil,
              let returnedID = json["model"] as? String, returnedID == modelID,
              let choices = json["choices"] as? [[String: Any]], choices.count == 1,
              let choice = choices.first, choice["finish_reason"] as? String == "stop",
              let message = choice["message"] as? [String: Any], message["role"] as? String == "assistant",
              message["tool_calls"] == nil || message["tool_calls"] is NSNull,
              message["function_call"] == nil || message["function_call"] is NSNull,
              let answer = message["content"] as? String,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenRouterFreeError.invalidResponse }
        return FreeOnlineCompletion(model: model, text: answer)
    }

    private func send(_ request: URLRequest, limit: Int) async throws -> Data {
        do {
            try Task.checkCancellation()
            let (data, response) = try await transport(request, limit)
            try Task.checkCancellation()
            guard response.url == request.url else { throw OpenRouterFreeError.invalidResponse }
            try Self.checkStatus(response.statusCode)
            guard data.count <= limit, response.mimeType?.lowercased() == "application/json" else { throw OpenRouterFreeError.invalidResponse }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as OpenRouterFreeError { throw error }
        catch { if Task.isCancelled { throw CancellationError() }; throw OpenRouterFreeError.networkUnavailable }
    }
    fileprivate static func checkStatus(_ status: Int) throws {
        switch status {
        case 200: break
        case 401, 403: throw OpenRouterFreeError.keyRejected
        case 429: throw OpenRouterFreeError.rateLimited
        case 402: throw OpenRouterFreeError.freeRouteUnavailable
        default: throw OpenRouterFreeError.networkUnavailable
        }
    }
    static func isConcreteFreeID(_ id: String) -> Bool {
        guard id.utf8.count <= 200, id.range(of: #"^[a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._-]*:free$"#, options: .regularExpression) != nil else { return false }
        let slug = id.split(separator: "/").last!.dropLast(5)
        return !["auto", "free", "router"].contains(String(slug))
    }
    /// Pure parser, also used by native tests. No catalog cache can authorize a POST.
    static func parseCatalog(_ data: Data, now: Date = Date()) throws -> [OpenRouterFreeModel] {
        guard data.count <= 4_194_304,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["error"] == nil,
              let rows = json["data"] as? [[String: Any]], rows.count <= 10_000 else { throw OpenRouterFreeError.invalidCatalog }
        var counts: [String: Int] = [:]
        for row in rows { if let id = row["id"] as? String { counts[id, default: 0] += 1 } }
        let knownPrices: Set<String> = ["prompt", "completion", "request", "image", "web_search", "internal_reasoning", "input_cache_read", "input_cache_write", "audio", "input_audio", "output_audio", "video"]
        func zero(_ value: Any?) -> Bool {
            guard let text = value as? String, !text.isEmpty, text.utf8.count <= 64,
                  text.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { return false }
            // Exact lexical decimal zero: no float rounding, exponents or underflow.
            return text.utf8.allSatisfy { $0 == 48 || $0 == 46 }
        }
        return rows.compactMap { row -> OpenRouterFreeModel? in
            guard let id = row["id"] as? String, counts[id] == 1, isConcreteFreeID(id),
                  let pricing = row["pricing"] as? [String: Any], zero(pricing["prompt"]), zero(pricing["completion"]),
                  pricing.allSatisfy({ knownPrices.contains($0.key) && zero($0.value) }),
                  let architecture = row["architecture"] as? [String: Any],
                  let inputs = architecture["input_modalities"] as? [String], inputs.contains("text"),
                  let outputs = architecture["output_modalities"] as? [String], outputs == ["text"],
                  let endpoints = row["endpoints"] as? [String], endpoints.contains("/api/v1/chat/completions") else { return nil }
            if let expiry = row["expiration_date"], !(expiry is NSNull) {
                guard let date = expiry as? String, date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
                guard let expires = formatter.date(from: date), formatter.string(from: expires) == date, expires > now else { return nil }
            }
            let rawName = (row["name"] as? String) ?? id
            let name = String(rawName.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(100).map(String.init).joined())
            return OpenRouterFreeModel(id: id, name: name.isEmpty ? id : name)
        }.sorted { $0.id < $1.id }
    }
}

struct FreeOnlineCompletion: Sendable {
    let model: OpenRouterFreeModel
    let text: String
}

/// Bounded on-device keyword heuristic, not a quality benchmark or another API call.
/// Input here is the current newly authored turn only. Unknown tasks use stable general fit.
enum FreeOnlineAutoRouter {
    static func classify(_ text: String) -> OpenRouterFreeModel.SuggestedUse {
        let prefix = String(text.prefix(4096)).lowercased()
        let words = Set(prefix.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if !words.isDisjoint(with: ["code", "coding", "debug", "bug", "swift", "python", "javascript", "typescript", "sql", "function", "compiler"]) || prefix.contains("```") { return .coding }
        if !words.isDisjoint(with: ["prove", "theorem", "equation", "math", "mathematics", "reasoning", "logic"]) || prefix.contains("step by step") { return .hardProblems }
        if !words.isDisjoint(with: ["write", "rewrite", "draft", "email", "letter", "poem", "story", "summarize", "reword", "proofread"]) { return .writing }
        return .everyday
    }

    /// Only called with freshly parsed eligible catalog rows, never a saved preview.
    static func select(text: String, verifiedModels: [OpenRouterFreeModel]) throws -> OpenRouterFreeModel {
        let task = classify(text)
        let ordered = verifiedModels.sorted { lhs, rhs in
            func rank(_ model: OpenRouterFreeModel) -> Int {
                if model.suggestedUses.first == task { return 0 }
                if model.suggestedUses.contains(task) { return 1 }
                if model.suggestedUses.first == .everyday { return 2 }
                return 3
            }
            let a = rank(lhs), b = rank(rhs)
            return a == b ? lhs.id < rhs.id : a < b
        }
        guard let model = ordered.first else { throw OpenRouterFreeError.modelUnavailable }
        return model
    }
}

struct OpenRouterFreeModel: Identifiable, Equatable, Sendable {
    enum SuggestedUse: String, CaseIterable, Sendable { case everyday = "Everyday", writing = "Writing", coding = "Coding", hardProblems = "Hard problems" }
    let id: String
    let name: String
    // Controlled editorial suggestions from the official catalog snapshot, 2026-11-20.
    // Profiles describe possible uses, not measured quality, speed or app capabilities.
    // This table never admits a model: live free-price validation remains independent.
    private struct Profile {
        let uses: [SuggestedUse]
        let note: String
    }
    private var profile: Profile {
        switch id {
        case "baidu/ernie-5.5-flash-preview:free":
            return Profile(uses: [.coding, .writing, .everyday], note: "ERNIE preview: try code explanations or drafting work notes. This chat cannot browse or do research for you.")
        case "dots-studio/dots-3-note-preview:free":
            return Profile(uses: [.everyday, .writing], note: "Dots Note preview: try everyday questions or rewriting a short note. A lighter model in its family; quality here has not been measured.")
        case "google/gemma-4-26b-a4b-it:free":
            return Profile(uses: [.everyday, .writing], note: "Gemma 26B: try following writing instructions, rewording a paragraph or explaining an idea. Its larger-model features are not all available here.")
        case "google/gemma-4-31b-it:free":
            return Profile(uses: [.hardProblems, .everyday, .writing], note: "Gemma 31B: try explaining a tricky question or comparing written options. The catalog lists reasoning support; this app does not expose a thinking-mode control.")
        case "inclusionai/ling-3.2-flash:free":
            return Profile(uses: [.hardProblems, .everyday], note: "Ling Flash: try breaking a problem into steps. It is described as a reasoning model; answers still need checking.")
        case "liquid/lfm-3-1.7b:free":
            return Profile(uses: [.hardProblems, .writing, .everyday], note: "Liquid LFM3: try a structured list or a step-by-step explanation. The catalog warns the provider may retain prompts and replies; avoid private information.")
        case "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free":
            return Profile(uses: [.hardProblems, .everyday], note: "Nemotron Nano Omni: try explaining a situation you describe in words. Its image, audio and video abilities are not enabled in this chat.")
        case "nvidia/nemotron-3-ultra-550b-a55b:free":
            return Profile(uses: [.hardProblems, .everyday], note: "Nemotron Ultra: try comparing approaches to a complicated problem. It is described as a reasoning model, not a guarantee of correct answers.")
        case "nvidia/nemotron-3.5-lightning:free":
            return Profile(uses: [.everyday, .writing], note: "Nemotron Lightning: try a focused question or a short written task. Its agent-workflow focus does not give this chat tools or device control.")
        case "nvidia/nemotron-3.5-super-vl:free":
            return Profile(uses: [.everyday, .writing], note: "Nemotron Super VL: try a question or explanation using typed text. Despite its visual-model name, photos, documents and video cannot be attached here.")
        case "particle-ai/particle-1:free":
            return Profile(uses: [.coding, .everyday], note: "Particle: try understanding code, drafting a function or discussing a bug. Its coding-agent focus does not let this chat run commands or edit your files.")
        case "recursive/flint-v1.0:free":
            return Profile(uses: [.coding, .everyday], note: "Flint: try code suggestions or explaining an error message. Built for coding-agent use, but here it only replies with text and cannot test or run code.")
        default:
            return Profile(uses: [.everyday, .writing], note: "Try a general question or writing draft. This model's individual strengths have not been reviewed.")
        }
    }
    var suggestedUses: [SuggestedUse] { profile.uses }
    var shortDescription: String {
        profile.note + " Text only here; needs internet; free usage limits apply."
    }
    /// Search remains open to new catalog entries and includes descriptions, not only labels.
    func matchesSearch(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || ([id, name, shortDescription] + suggestedUses.map(\.rawValue))
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

}

enum OpenRouterFreeError: Error, LocalizedError, Equatable {
    case invalidCatalog, invalidResponse, modelUnavailable, keyRequired, keyRejected, promptTooLong, rateLimited, freeRouteUnavailable, networkUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidCatalog: return "The free model list could not be verified. Try refreshing it later or choose an offline AI."
        case .invalidResponse: return "The online reply could not be verified. Your message has not been retried."
        case .modelUnavailable: return "This model is no longer verified as free. Refresh the list or choose an offline AI."
        case .keyRequired: return "Enter your OpenRouter key to use Free Online. You can also choose an offline AI."
        case .keyRejected: return "OpenRouter did not accept access. Check your key or choose an offline AI."
        case .promptTooLong: return "Type a message of up to 24,000 UTF-8 bytes for this online turn."
        case .rateLimited: return "The free usage limit has been reached. Try later or choose an offline AI. No paid model was used."
        case .freeRouteUnavailable: return "No free route is available right now. Choose an offline AI or try later. No paid fallback was requested."
        case .networkUnavailable: return "Free Online could not connect. Try later or choose an offline AI."
        }
    }
}

/// One ephemeral session per bounded request; no shared cookies, credentials, disk
/// cache, redirect, background upload, retry or configurable URL. Body limits are
/// enforced during receipt, not just after URLSession has buffered an entire body.
private final class FreeChatHTTP: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var session: URLSession?
    private var data = Data()
    private var response: HTTPURLResponse?
    private var cancelled = false
    private let limit: Int
    private let url: URL
    private init(url: URL, limit: Int) { self.url = url; self.limit = limit }
    static func perform(_ request: URLRequest, limit: Int) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, [OpenRouterFreeProvider.catalogURL, OpenRouterFreeProvider.completionURL].contains(url) else { throw OpenRouterFreeError.invalidResponse }
        let operation = FreeChatHTTP(url: url, limit: limit)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { operation.start(request, continuation: $0) }
        }, onCancel: { operation.cancel() })
    }
    private func start(_ request: URLRequest, continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        guard !cancelled else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 90
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        lock.unlock()
        task.resume()
    }
    private func cancel() { lock.lock(); cancelled = true; lock.unlock(); finish(.failure(CancellationError())) }
    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock(); let continuation = self.continuation; self.continuation = nil; let session = self.session; self.session = nil; data.removeAll(); lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        #if canImport(Security)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust { completionHandler(.performDefaultHandling, nil); return }
        #endif
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.url == url else {
            completionHandler(.cancel); finish(.failure(OpenRouterFreeError.invalidResponse)); return
        }
        do { try OpenRouterFreeProvider.checkStatus(http.statusCode) }
        catch { completionHandler(.cancel); finish(.failure(error)); return }
        guard http.mimeType?.lowercased() == "application/json", http.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(.failure(OpenRouterFreeError.invalidResponse)); return
        }
        lock.lock(); self.response = http; lock.unlock(); completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        guard continuation != nil else { lock.unlock(); return }
        guard chunk.count <= limit - data.count else { lock.unlock(); finish(.failure(OpenRouterFreeError.invalidResponse)); return }
        data.append(chunk); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let response = self.response; let body = data; lock.unlock()
        if let error { finish(.failure(error)) }
        else if let response { finish(.success((body, response))) }
        else { finish(.failure(OpenRouterFreeError.invalidResponse)) }
    }
}
