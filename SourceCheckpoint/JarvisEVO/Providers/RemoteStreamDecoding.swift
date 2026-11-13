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
    private var receivedStop = false
    private var receivedDone = false
    private struct Envelope: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                // These payloads are not executed by this text-only provider.
                struct UnsupportedCall: Decodable {}
                let content: String?
                let refusal: String?
                let tool_calls: [UnsupportedCall]?
                let function_call: UnsupportedCall?
            }
            let delta: Delta?
            let finish_reason: String?
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
        guard !receivedDone else { throw ProviderError.invalidResponse }
        if text == "[DONE]" {
            guard receivedStop else { throw ProviderError.rejected("The provider ended the stream without confirming a complete response. Any partial response is kept.") }
            receivedDone = true
            return .done
        }
        guard let value = try? JSONDecoder().decode(Envelope.self, from: Data(text.utf8)) else { throw ProviderError.invalidResponse }
        if value.error != nil { throw ProviderError.rejected("The provider rejected the request. Check its credentials, model and usage limits.") }
        guard let choice = value.choices?.first else { return .ignored }
        guard choice.delta?.tool_calls == nil, choice.delta?.function_call == nil else {
            throw ProviderError.rejected("The provider requested a tool or function call that this text connection does not support. No tool was executed.")
        }
        guard choice.delta?.refusal == nil else {
            throw ProviderError.rejected("The provider declined this response under its policy. Any partial response is kept and is not marked complete.")
        }
        guard !receivedStop || choice.finish_reason == nil else { throw ProviderError.invalidResponse }
        if let reason = choice.finish_reason, reason != "stop" {
            switch reason {
            case "length": throw ProviderError.rejected("The provider reached its output limit before finishing. Any partial response is kept; ask for a shorter answer or retry.")
            case "content_filter": throw ProviderError.rejected("The provider stopped this response under its content policy. Any partial response is kept and is not marked complete.")
            case "tool_calls", "function_call": throw ProviderError.rejected("The provider requires an unsupported tool or function call to finish. No tool was executed.")
            default: throw ProviderError.rejected("The provider returned an unsupported completion status. Any partial response is kept and is not marked complete.")
            }
        }
        let content = choice.delta?.content ?? ""
        guard !receivedStop || content.isEmpty else { throw ProviderError.invalidResponse }
        if choice.finish_reason == "stop" { receivedStop = true }
        guard !content.isEmpty else { return .ignored }
        return .token(content)
    }
}

/// Bounds each event while receiving bytes, before a remote peer can allocate an unbounded line.
struct SSEByteDecoder {
    private var bytes: [UInt8] = []
    private var decoder = SSEDecoder()
    private var previousWasCR = false
    let maximumLineBytes: Int
    init(maximumLineBytes: Int = 1_000_000) { self.maximumLineBytes = maximumLineBytes }
    mutating func consume(byte: UInt8) throws -> SSEEvent? {
        // SSE permits LF, CRLF and lone CR. A CR dispatches immediately; only
        // its following LF is swallowed, so delimiters never consume line budget.
        if previousWasCR {
            previousWasCR = false
            if byte == 10 { return nil }
        }
        if byte == 10 || byte == 13 {
            previousWasCR = byte == 13
            guard let line = String(bytes: bytes, encoding: .utf8) else { throw ProviderError.invalidResponse }
            bytes.removeAll(keepingCapacity: true)
            return try decoder.consume(line: line)
        }
        guard bytes.count < maximumLineBytes else { throw ProviderError.invalidResponse }
        bytes.append(byte)
        return nil
    }
}

