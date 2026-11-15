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
            let index: Int?
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
        guard let choices = value.choices, !choices.isEmpty else { return .ignored }
        // This connection requests one answer. Never stitch another choice's text
        // into it or let another choice's stop mark the displayed answer complete.
        // Older compatible servers may omit index for their sole choice.
        guard choices.count == 1, let choice = choices.first,
              choice.index == nil || choice.index == 0 else { throw ProviderError.invalidResponse }
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

/// Bounded SSE line and event framing. Only a blank line dispatches data;
/// incomplete events at EOF never become a completed provider response.
struct SSEByteDecoder {
    private var bytes: [UInt8] = []
    private var decoder = SSEDecoder()
    private var previousWasCR = false
    private var firstLine = true
    private var eventData = ""
    private var eventBytes = 0
    private var hasData = false
    let maximumLineBytes: Int
    let maximumEventBytes: Int
    init(maximumLineBytes: Int = 1_000_000, maximumEventBytes: Int = 999_995) {
        self.maximumLineBytes = max(0, maximumLineBytes)
        // SSEDecoder's payload interface adds the five-byte data: field prefix.
        self.maximumEventBytes = max(0, min(999_995, maximumEventBytes))
    }
    mutating func consume(byte: UInt8) throws -> SSEEvent? {
        if previousWasCR {
            previousWasCR = false
            if byte == 10 { return nil }
        }
        if byte == 10 || byte == 13 {
            previousWasCR = byte == 13
            guard var line = String(bytes: bytes, encoding: .utf8) else { throw ProviderError.invalidResponse }
            bytes.removeAll(keepingCapacity: true)
            if firstLine {
                firstLine = false
                if line.unicodeScalars.first?.value == 0xfeff { line.unicodeScalars.removeFirst() }
            }
            return try consumeLine(line)
        }
        guard bytes.count < maximumLineBytes else { throw ProviderError.invalidResponse }
        bytes.append(byte)
        return nil
    }
    private mutating func consumeLine(_ line: String) throws -> SSEEvent? {
        if line.isEmpty {
            guard hasData else { return nil }
            let payload = eventData
            eventData = ""; eventBytes = 0; hasData = false
            return try decoder.consume(line: "data:" + payload)
        }
        // Ignore comments and unknown/metadata fields. They never become model text.
        let raw = line.utf8
        var value: String
        if raw.elementsEqual("data".utf8) { value = "" }
        else if raw.starts(with: "data:".utf8) {
            let payload = raw.dropFirst(5)
            value = String(decoding: payload.first == 32 ? payload.dropFirst() : payload, as: UTF8.self)
        } else { return nil }
        let separatorBytes = hasData ? 1 : 0
        let count = value.utf8.count
        guard separatorBytes <= maximumEventBytes - eventBytes,
              count <= maximumEventBytes - eventBytes - separatorBytes else { throw ProviderError.invalidResponse }
        if hasData { eventData += "\n" }
        eventData += value
        eventBytes += count + separatorBytes
        hasData = true
        return nil
    }
}
