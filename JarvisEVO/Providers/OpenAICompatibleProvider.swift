import Foundation

struct RemoteEndpoint: Sendable {
    let baseURL: URL
    let model: String
    init(baseURL: String, model: String) throws {
        guard let components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              let url = components.url else { throw ProviderError.invalidEndpoint }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, model.utf8.count <= 256 else { throw ProviderError.invalidModel }
        self.baseURL = url
        self.model = model
    }
}

enum SSEEvent: Equatable { case token(String), done, ignored }
struct SSEDecoder {
    private struct Envelope: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        struct Failure: Decodable { let message: String? }
        let choices: [Choice]?
        let error: Failure?
    }
    mutating func consume(line: String) throws -> SSEEvent {
        guard line.utf8.count <= 1_000_000 else { throw ProviderError.invalidResponse }
        guard line.hasPrefix("data:") else { return .ignored }
        let text = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .ignored }
        if text == "[DONE]" { return .done }
        guard let value = try? JSONDecoder().decode(Envelope.self, from: Data(text.utf8)) else { throw ProviderError.invalidResponse }
        if value.error != nil { throw ProviderError.rejected("The provider rejected the request. Check its credentials, model and usage limits.") }
        guard let content = value.choices?.first?.delta?.content, !content.isEmpty else { return .ignored }
        return .token(content)
    }
}

/// Bounds each event while receiving bytes, before a remote peer can allocate an unbounded line.
struct SSEByteDecoder {
    private var bytes: [UInt8] = []
    private var decoder = SSEDecoder()
    let maximumLineBytes: Int
    init(maximumLineBytes: Int = 1_000_000) { self.maximumLineBytes = maximumLineBytes }
    mutating func consume(byte: UInt8) throws -> SSEEvent? {
        if byte == 10 {
            if bytes.last == 13 { bytes.removeLast() }
            guard let line = String(bytes: bytes, encoding: .utf8) else { throw ProviderError.invalidResponse }
            bytes.removeAll(keepingCapacity: true)
            return try decoder.consume(line: line)
        }
        guard bytes.count < maximumLineBytes else { throw ProviderError.invalidResponse }
        bytes.append(byte)
        return nil
    }
}

/// Rejects every redirect so an Authorization header cannot reach another destination.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct OpenAICompatibleProvider: AIProvider {
    let endpoint: RemoteEndpoint
    private let apiKey: String?
    var id: String { "remote:\(endpoint.baseURL.absoluteString):\(endpoint.model)" }
    var displayName: String { endpoint.model }
    init(endpoint: RemoteEndpoint, apiKey: String? = nil) { self.endpoint = endpoint; self.apiKey = apiKey }

    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        var urlRequest = URLRequest(url: endpoint.baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty { urlRequest.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization") }
        let context = try ContextWindow.trim(request.messages, characterBudget: 24_000 - request.systemPrompt.count)
        guard context.contains(where: { $0.role == .user }) else { throw ProviderError.rejected("The latest message is too large for this provider. Shorten it and try again.") }
        let messages = [["role": "system", "content": request.systemPrompt]] + context.map { ["role": $0.role.rawValue, "content": $0.promptContent] }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": endpoint.model, "messages": messages, "stream": true,
            "max_tokens": max(1, min(request.maxTokens, 4_096)), "temperature": max(0, min(request.temperature, 2))
        ])
        let preparedRequest = urlRequest
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 300
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        return AsyncThrowingStream { continuation in
            let task = Task {
                defer { session.invalidateAndCancel() }
                do {
                    let (bytes, response) = try await session.bytes(for: preparedRequest)
                    guard let response = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
                    guard (200..<300).contains(response.statusCode) else { throw ProviderError.server(response.statusCode) }
                    guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else { throw ProviderError.invalidResponse }
                    var decoder = SSEByteDecoder()
                    var outputCount = 0
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard let event = try decoder.consume(byte: byte) else { continue }
                        switch event {
                        case .token(let token):
                            outputCount += token.utf8.count
                            guard outputCount <= 2_000_000 else { throw ProviderError.invalidResponse }
                            continuation.yield(token)
                        case .done:
                            guard outputCount > 0 else { throw ProviderError.emptyResponse }
                            continuation.finish()
                            return
                        case .ignored: break
                        }
                    }
                    throw ProviderError.rejected("The connection ended before the response finished. Your partial response has been kept.")
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
