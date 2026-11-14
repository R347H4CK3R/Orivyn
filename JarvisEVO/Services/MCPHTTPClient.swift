import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Tool-only, bounded MCP 2025-06-18. The caller is the permission broker: this
/// transport neither grants approval nor feeds server text to a model.
actor MCPHTTPClient {
    private static let version = "2025-06-18"
    private static let clientVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    private let endpoint: MCPEndpoint
    private var bearerToken: String?
    private let transport: any MCPHTTPTransport
    private var sessionID: String?
    private var serverInfo: MCPServerInfo?
    private var ready = false
    private var closed = false
    private var catalog: [String: MCPToolDefinition] = [:]
    private var catalogRevision = UUID()
    private var operation: Operation?

    private struct Operation {
        let id: UUID
        var rpcID: String?
        var method: String?
        var task: Task<MCPHTTPResponse, any Error>?
    }

    init(endpoint: MCPEndpoint, bearerToken: String? = nil,
         transport: any MCPHTTPTransport = URLSessionMCPTransport()) throws {
        if let token = bearerToken {
            guard !token.isEmpty, token.utf8.count <= 8_192,
                  token.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else { throw MCPClientFailure(.invalidCredential) }
        }
        self.endpoint = endpoint; self.bearerToken = bearerToken; self.transport = transport
    }

    func initialize() async throws -> MCPServerInfo {
        guard !closed else { throw MCPClientFailure(.closed) }
        guard operation == nil else { throw MCPClientFailure(.busy) }
        if ready, let serverInfo { return serverInfo }
        let owner = try begin(requireReady: false)
        defer { finish(owner) }
        sessionID = nil; serverInfo = nil; catalog = [:]; ready = false
        do {
            let (result, response) = try await rpc("initialize", params: .object([
                "protocolVersion": .string(Self.version), "capabilities": .object([:]),
                "clientInfo": .object(["name": .string("Orivyn"), "version": .string(Self.clientVersion)])
            ]), owner: owner)
            guard let object = result.objectValue else { throw MCPClientFailure(.invalidResponse) }
            guard object["protocolVersion"]?.stringValue == Self.version else { throw MCPClientFailure(.unsupportedVersion) }
            guard object["capabilities"]?.objectValue?["tools"]?.objectValue != nil,
                  let info = object["serverInfo"]?.objectValue,
                  let name = bounded(info["name"], bytes: 128), let version = bounded(info["version"], bytes: 128) else {
                throw MCPClientFailure(.invalidResponse)
            }
            sessionID = try headers(response)["mcp-session-id"]
            try await notify("notifications/initialized", params: nil, owner: owner)
            try checkOwner(owner)
            let server = MCPServerInfo(name: name, version: version)
            serverInfo = server; ready = true
            return server
        } catch {
            if operation?.id == owner { ready = false; catalog = [:] }
            throw failure(error)
        }
    }

    func listTools() async throws -> [MCPToolDefinition] {
        let owner = try begin(requireReady: true)
        defer { finish(owner) }
        catalog = [:]
        let startingRevision = catalogRevision
        var collected: [MCPToolDefinition] = []
        var names = Set<String>(), cursors = Set<String>()
        var cursor: String?
        for page in 0..<8 {
            let params: MCPJSONValue = .object(cursor.map { ["cursor": .string($0)] } ?? [:])
            let (result, _) = try await rpc("tools/list", params: params, owner: owner)
            guard catalogRevision == startingRevision else { throw MCPClientFailure(.unknownTool) }
            guard let object = result.objectValue, let tools = object["tools"]?.arrayValue else { throw MCPClientFailure(.invalidResponse) }
            for raw in tools {
                guard collected.count < 32 else { throw MCPClientFailure(.responseTooLarge) }
                let tool = try definition(raw)
                guard names.insert(tool.name).inserted else { throw MCPClientFailure(.invalidResponse) }
                collected.append(tool)
            }
            if let raw = object["nextCursor"] {
                guard let next = bounded(raw, bytes: 1_024), cursors.insert(next).inserted, page < 7 else { throw MCPClientFailure(.invalidResponse) }
                cursor = next
            } else {
                try checkOwner(owner)
                catalog = Dictionary(uniqueKeysWithValues: collected.map { ($0.name, $0) })
                return collected
            }
        }
        throw MCPClientFailure(.responseTooLarge)
    }

    /// Only the broker may call after an explicit immutable user review. Cached
    /// annotations are never consulted as authority; all argument checks precede POST.
    func callTool(named name: String, arguments: MCPJSONValue) async throws -> MCPToolCallResult {
        guard !closed else { throw MCPClientFailure(.closed) }
        guard ready else { throw MCPClientFailure(.notInitialized) }
        guard operation == nil else { throw MCPClientFailure(.busy) }
        guard let tool = catalog[name] else { throw MCPClientFailure(.unknownTool) }
        do {
            guard arguments.objectValue != nil else { throw MCPClientFailure(.invalidArguments) }
            _ = try arguments.encoded(maximumBytes: 16_384)
            try tool.inputSchema.validate(arguments)
        } catch { throw MCPClientFailure(.invalidArguments) }
        let owner = try begin(requireReady: true)
        defer { finish(owner) }
        let (result, _) = try await rpc("tools/call", params: .object(["name": .string(name), "arguments": arguments]), owner: owner)
        do { return try callResult(result, tool: tool) }
        catch { throw failure(error, uncertain: true) }
    }

    func cancelCurrentOperation() async {
        guard let old = operation else { return }
        operation = nil // Retire before any await or network cleanup.
        old.task?.cancel()
        if old.method == "initialize" { ready = false; catalog = [:]; sessionID = nil }
        if let id = old.rpcID, old.method != "initialize" {
            await bestEffortCancellation(id)
        }
    }

    func close() async {
        guard !closed else { return }
        closed = true; ready = false; catalog = [:]; serverInfo = nil
        let old = operation; operation = nil; old?.task?.cancel()
        let session = sessionID
        if let id = old?.rpcID, old?.method != "initialize" { await bestEffortCancellation(id) }
        // Prepare the optional session close before discarding the secret. No later
        // public call can reuse this client, including while DELETE is pending.
        var request = baseRequest(method: "DELETE")
        request.setValue(session, forHTTPHeaderField: "Mcp-Session-Id")
        bearerToken = nil; sessionID = nil
        if session != nil { _ = try? await transport.send(request, maximumResponseBytes: 1_048_576, timeout: 2) }
    }

    private func begin(requireReady: Bool) throws -> UUID {
        guard !closed else { throw MCPClientFailure(.closed) }
        guard operation == nil else { throw MCPClientFailure(.busy) }
        guard !requireReady || ready else { throw MCPClientFailure(.notInitialized) }
        let id = UUID(); operation = Operation(id: id); return id
    }
    private func finish(_ id: UUID) { if operation?.id == id { operation = nil } }
    private func checkOwner(_ id: UUID) throws {
        try Task.checkCancellation()
        guard !closed, operation?.id == id else { throw MCPClientFailure(.cancelled) }
    }
    private func baseRequest(method: String = "POST") -> URLRequest {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Self.version, forHTTPHeaderField: "MCP-Protocol-Version")
        if let token = bearerToken { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        return request
    }
    private func rpc(_ method: String, params: MCPJSONValue, owner: UUID) async throws -> (MCPJSONValue, MCPHTTPResponse) {
        try checkOwner(owner)
        let id = UUID().uuidString
        let envelope: MCPJSONValue = .object(["jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method), "params": params])
        var request = baseRequest()
        request.httpBody = try envelope.encoded(maximumBytes: 32_768)
        operation?.rpcID = id; operation?.method = method
        do {
            let response = try await exchange(request, owner: owner, initializing: method == "initialize")
            guard response.statusCode == 200 else { throw MCPClientFailure(.http(response.statusCode)) }
            let result = try parseResponse(response, expectedID: id)
            return (result, response)
        } catch { throw failure(error, uncertain: method == "tools/call") }
    }
    private func notify(_ method: String, params: MCPJSONValue?, owner: UUID) async throws {
        var object: [String: MCPJSONValue] = ["jsonrpc": .string("2.0"), "method": .string(method)]
        if let params { object["params"] = params }
        var request = baseRequest(); request.httpBody = try MCPJSONValue.object(object).encoded()
        operation?.rpcID = nil; operation?.method = method
        let response = try await exchange(request, owner: owner)
        guard response.statusCode == 202, response.body.isEmpty else { throw MCPClientFailure(.invalidResponse) }
    }
    private func exchange(_ request: URLRequest, owner: UUID, initializing: Bool = false) async throws -> MCPHTTPResponse {
        try checkOwner(owner)
        let transport = self.transport
        let task = Task { try await transport.send(request, maximumResponseBytes: 1_048_576, timeout: 30) }
        operation?.task = task
        let response: MCPHTTPResponse
        do {
            response = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        } catch { throw failure(error) }
        try checkOwner(owner)
        operation?.task = nil
        guard response.url == endpoint.url else { throw MCPClientFailure(.redirect) }
        guard response.body.count <= 1_048_576 else { throw MCPClientFailure(.responseTooLarge) }
        if (300..<400).contains(response.statusCode) { throw MCPClientFailure(.redirect) }
        if response.statusCode == 404, sessionID != nil {
            ready = false; catalog = [:]; sessionID = nil
            throw MCPClientFailure(.sessionExpired)
        }
        guard (200..<300).contains(response.statusCode) else { throw MCPClientFailure(.http(response.statusCode)) }
        let h = try headers(response)
        if let version = h["mcp-protocol-version"], version != Self.version { throw MCPClientFailure(.unsupportedVersion) }
        if let session = h["mcp-session-id"] {
            guard !session.isEmpty, session.utf8.count <= 1_024,
                  session.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }),
                  initializing || session == sessionID else { throw MCPClientFailure(.invalidResponse) }
        }
        return response
    }
    private func headers(_ response: MCPHTTPResponse) throws -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response.headers {
            let key = key.lowercased()
            guard result[key] == nil, key.utf8.count <= 256, value.utf8.count <= 8_192 else { throw MCPClientFailure(.invalidResponse) }
            result[key] = value
        }
        return result
    }
    private func parseResponse(_ response: MCPHTTPResponse, expectedID: String) throws -> MCPJSONValue {
        let type = try headers(response)["content-type"]?.lowercased() ?? ""
        let mediaType = type.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""
        let messages: [MCPJSONValue]
        switch mediaType {
        case "application/json": messages = [try MCPJSONValue.parse(response.body)]
        case "text/event-stream":
            guard !type.contains("charset=") || type.contains("charset=utf-8") || type.contains("charset=\"utf-8\"") else { throw MCPClientFailure(.unsupportedTransport) }
            messages = try sseMessages(response.body)
        default: throw MCPClientFailure(.unsupportedTransport)
        }
        var reply: MCPJSONValue?
        for message in messages {
            guard let object = message.objectValue, object["jsonrpc"]?.stringValue == "2.0" else { throw MCPClientFailure(.invalidResponse) }
            if let method = object["method"] {
                guard object["id"] == nil, let method = method.stringValue,
                      method.hasPrefix("notifications/"), object["result"] == nil, object["error"] == nil else { throw MCPClientFailure(.unsupportedTransport) }
                if method == "notifications/tools/list_changed" { catalog = [:]; catalogRevision = UUID() }
                continue // Data-only notifications never cause external calls.
            }
            guard object["id"] == .string(expectedID), reply == nil,
                  (object["result"] != nil) != (object["error"] != nil) else { throw MCPClientFailure(.invalidResponse) }
            if let error = object["error"]?.objectValue {
                guard let code = error["code"]?.integerValue, error["message"]?.stringValue != nil,
                      let code = Int(exactly: code) else { throw MCPClientFailure(.invalidResponse) }
                throw MCPClientFailure(.rpc(code))
            }
            guard let result = object["result"] else { throw MCPClientFailure(.invalidResponse) }
            reply = result
        }
        guard let reply else { throw MCPClientFailure(.invalidResponse) }
        return reply
    }
    private func sseMessages(_ data: Data) throws -> [MCPJSONValue] {
        guard let text = String(data: data, encoding: .utf8) else { throw MCPClientFailure(.invalidResponse) }
        var messages: [MCPJSONValue] = [], lines: [String] = [], event = ""
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in normalized.components(separatedBy: "\n") {
            if raw.isEmpty {
                if !lines.isEmpty {
                    guard event.isEmpty || event == "message", messages.count < 128 else { throw MCPClientFailure(.unsupportedTransport) }
                    messages.append(try MCPJSONValue.parse(Data(lines.joined(separator: "\n").utf8)))
                }
                lines = []; event = ""; continue
            }
            if raw.hasPrefix(":") { continue }
            let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            var value = parts.count == 2 ? String(parts[1]) : ""
            if value.hasPrefix(" ") { value.removeFirst() }
            switch parts[0] {
            case "data": lines.append(value)
            case "event": event = value
            case "id": guard value.utf8.count <= 1_024, !value.contains("\0") else { throw MCPClientFailure(.invalidResponse) }
            case "retry": break // No reconnect or resumption is performed.
            default: break
            }
        }
        guard lines.isEmpty, event.isEmpty else { throw MCPClientFailure(.invalidResponse) }
        return messages
    }
    private func definition(_ raw: MCPJSONValue) throws -> MCPToolDefinition {
        guard let object = raw.objectValue, let name = bounded(object["name"], bytes: 128),
              name.rangeOfCharacter(from: .controlCharacters) == nil,
              let schema = object["inputSchema"] else { throw MCPClientFailure(.invalidResponse) }
        var tool = MCPToolDefinition(name: name, inputSchema: try MCPToolSchema(json: schema))
        for key in ["title", "description"] where object[key] != nil {
            guard let text = object[key]?.stringValue, text.utf8.count <= 4_096 else { throw MCPClientFailure(.invalidResponse) }
            if key == "title" { tool.title = text } else { tool.description = text }
        }
        if let output = object["outputSchema"] { tool.outputSchema = try MCPToolSchema(json: output) }
        if let annotations = object["annotations"] {
            guard annotations.objectValue != nil else { throw MCPClientFailure(.invalidResponse) }
            tool.annotations = annotations
        }
        return tool
    }
    private func callResult(_ raw: MCPJSONValue, tool: MCPToolDefinition) throws -> MCPToolCallResult {
        guard let object = raw.objectValue, let blocks = object["content"]?.arrayValue, blocks.count <= 32 else { throw MCPClientFailure(.invalidResponse) }
        if let error = object["isError"], error.boolValue == nil { throw MCPClientFailure(.invalidResponse) }
        var content: [MCPContent] = []
        for block in blocks {
            guard let item = block.objectValue, let type = item["type"]?.stringValue else { throw MCPClientFailure(.invalidResponse) }
            switch type {
            case "text":
                guard let text = item["text"]?.stringValue else { throw MCPClientFailure(.invalidResponse) }
                content.append(.text(text))
            case "image":
                guard let encoded = item["data"]?.stringValue, let mime = item["mimeType"]?.stringValue,
                      ["image/png", "image/jpeg", "image/webp", "image/gif"].contains(mime),
                      let data = Data(base64Encoded: encoded), data.count <= 786_432 else { throw MCPClientFailure(.invalidResponse) }
                content.append(.image(data: data, mimeType: mime))
            default: throw MCPClientFailure(.unsupportedTransport)
            }
        }
        let structured = object["structuredContent"]
        if let structured, structured.objectValue == nil { throw MCPClientFailure(.invalidResponse) }
        if let schema = tool.outputSchema {
            guard let structured else { throw MCPClientFailure(.invalidResponse) }
            do { try schema.validate(structured) }
            catch { throw MCPClientFailure(.invalidResponse) }
        }
        return MCPToolCallResult(content: content, structuredContent: structured, isError: object["isError"]?.boolValue ?? false)
    }
    private func bounded(_ raw: MCPJSONValue?, bytes: Int) -> String? {
        guard let value = raw?.stringValue, !value.isEmpty, value.utf8.count <= bytes else { return nil }; return value
    }
    private func bestEffortCancellation(_ id: String) async {
        let object: MCPJSONValue = .object(["jsonrpc": .string("2.0"), "method": .string("notifications/cancelled"),
            "params": .object(["requestId": .string(id), "reason": .string("Canceled by client")])])
        var request = baseRequest(); request.httpBody = try? object.encoded()
        _ = try? await transport.send(request, maximumResponseBytes: 1_048_576, timeout: 2)
    }
    private func failure(_ error: any Error, uncertain: Bool = false) -> MCPClientFailure {
        if let failure = error as? MCPClientFailure { return MCPClientFailure(failure.code, effectMayHaveOccurred: uncertain || failure.effectMayHaveOccurred) }
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return MCPClientFailure(.cancelled, effectMayHaveOccurred: uncertain) }
        if (error as? URLError)?.code == .timedOut { return MCPClientFailure(.timedOut, effectMayHaveOccurred: uncertain) }
        return MCPClientFailure(.network, effectMayHaveOccurred: uncertain)
    }
}

/// A fresh ephemeral session per request, with an independent bounded delegate.
/// The private copied configuration is never mutated after initialization.
final class URLSessionMCPTransport: MCPHTTPTransport, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
    }
    func send(_ request: URLRequest, maximumResponseBytes: Int, timeout: TimeInterval) async throws -> MCPHTTPResponse {
        guard let url = request.url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              (1...1_048_576).contains(maximumResponseBytes), timeout.isFinite, timeout > 0, timeout <= 30 else { throw MCPClientFailure(.invalidEndpoint) }
        let configuration = lock.withLock { self.configuration.copy() as! URLSessionConfiguration }
        configuration.urlCache = nil; configuration.urlCredentialStorage = nil; configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false; configuration.httpCookieAcceptPolicy = .never
        configuration.httpAdditionalHeaders = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        #if !os(Linux)
        configuration.waitsForConnectivity = false
        #endif
        configuration.timeoutIntervalForRequest = timeout; configuration.timeoutIntervalForResource = timeout
        let receiver = MCPBoundedReceiver(limit: maximumResponseBytes)
        return try await receiver.perform(request, configuration: configuration, timeout: timeout)
    }
}

/// All mutable delegate/continuation state is lock-protected. Finish takes ownership
/// once, then resumes outside the lock. No error exposes response text or credentials.
private final class MCPBoundedReceiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var body = Data()
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<MCPHTTPResponse, any Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var deadline: DispatchWorkItem?
    private var terminal: Result<MCPHTTPResponse, any Error>?
    init(limit: Int) { self.limit = limit }

    func perform(_ request: URLRequest, configuration: URLSessionConfiguration, timeout: TimeInterval) async throws -> MCPHTTPResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let launch: URLSessionDataTask? = lock.withLock {
                    if let terminal { continuation.resume(with: terminal); return nil }
                    self.continuation = continuation
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                    self.session = session
                    let task = session.dataTask(with: request); self.task = task
                    let deadline = DispatchWorkItem { [weak self] in self?.finish(.failure(MCPClientFailure(.timedOut))) }
                    self.deadline = deadline
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                    return task
                }
                launch?.resume()
            }
        } onCancel: { self.finish(.failure(MCPClientFailure(.cancelled))) }
    }
    private func finish(_ result: Result<MCPHTTPResponse, any Error>) {
        let owned: (CheckedContinuation<MCPHTTPResponse, any Error>?, URLSession?, URLSessionDataTask?)? = lock.withLock {
            guard terminal == nil else { return nil }
            terminal = result; deadline?.cancel(); deadline = nil
            let owned = (continuation, session, task)
            continuation = nil; session = nil; task = nil; body = Data(); response = nil
            return owned
        }
        guard let owned else { return }
        owned.2?.cancel(); owned.1?.invalidateAndCancel(); owned.0?.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel); finish(.failure(MCPClientFailure(.invalidResponse))); return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(.failure(MCPClientFailure(.responseTooLarge))); return
        }
        let accepted = lock.withLock {
            guard terminal == nil, self.response == nil else { return false }
            self.response = response; return true
        }
        completionHandler(accepted ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overflow = lock.withLock {
            guard terminal == nil else { return false }
            guard data.count <= limit - body.count else { return true }
            body.append(data); return false
        }
        if overflow { finish(.failure(MCPClientFailure(.responseTooLarge))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(MCPClientFailure(.redirect)))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            let code: MCPFailureCode = (error as? URLError)?.code == .cancelled ? .cancelled : ((error as? URLError)?.code == .timedOut ? .timedOut : .network)
            finish(.failure(MCPClientFailure(code))); return
        }
        let result: MCPHTTPResponse? = lock.withLock {
            guard terminal == nil, let response, let url = response.url else { return nil }
            var headers: [String: String] = [:]
            for (key, value) in response.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
            return MCPHTTPResponse(url: url, statusCode: response.statusCode, headers: headers, body: body)
        }
        if let result { finish(.success(result)) }
        else { finish(.failure(MCPClientFailure(.invalidResponse))) }
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // In particular, never accept an invalid/self-signed server trust challenge.
        completionHandler(.performDefaultHandling, nil)
    }
}
