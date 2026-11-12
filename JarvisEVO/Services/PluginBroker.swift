import Foundation
import Observation

protocol PluginMCPClient: Sendable {
    func initialize() async throws -> MCPServerInfo
    func listTools() async throws -> [MCPToolDefinition]
    func callTool(named: String, arguments: MCPJSONValue) async throws -> MCPToolCallResult
    func cancelCurrentOperation() async
    func close() async
}
extension MCPHTTPClient: PluginMCPClient { }

struct PluginConnectionRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let endpoint: String
    let name: String
    let version: String
    let installedAt: Date
    var hasSavedToken: Bool
}

@MainActor @Observable
final class PluginBroker {
    private struct Snapshot: Codable { var version = 1; var connections: [PluginConnectionRecord] }
    private let file: URL
    private let clientFactory: @MainActor (MCPEndpoint, String?) throws -> any PluginMCPClient
    let journal: PluginJournal
    private(set) var connections: [PluginConnectionRecord] = []
    private(set) var tools: [MCPToolDefinition] = []
    private(set) var stagedConnection: PluginConnectionRecord?
    private(set) var review: PluginCallReview?
    private(set) var lastResult: MCPToolCallResult?
    private(set) var activeConnection: PluginConnectionRecord?
    private(set) var isForeground = true
    private var operationID: UUID?
    private var activeExecution: UUID?
    private var client: (any PluginMCPClient)?
    private var catalogRevision = UUID()
    private var gate = PluginReviewGate()
    private var pendingToken: String?
    var isBusy: Bool { operationID != nil }
    var canReviewTools: Bool { activeConnection != nil && stagedConnection == nil && client != nil && isForeground && !isBusy }

    init(directory: URL, clientFactory: @escaping @MainActor (MCPEndpoint, String?) throws -> any PluginMCPClient = {
        try MCPHTTPClient(endpoint: $0, bearerToken: $1)
    }) throws {
        self.clientFactory = clientFactory
        file = directory.appendingPathComponent("plugin-connections.json")
        journal = try PluginJournal(directory: directory)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, let size = values.fileSize, size <= 65_536 else { throw PluginBrokerError.metadata }
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
            guard snapshot.version == 1, snapshot.connections.count <= 8,
                  Set(snapshot.connections.map(\.id)).count == snapshot.connections.count,
                  Set(snapshot.connections.map(\.endpoint)).count == snapshot.connections.count else { throw PluginBrokerError.metadata }
            for item in snapshot.connections {
                _ = try MCPEndpoint.validated(item.endpoint)
                guard Self.validInfo(name: item.name, version: item.version), item.installedAt.timeIntervalSince1970.isFinite else { throw PluginBrokerError.metadata }
            }
            connections = snapshot.connections
        } catch { throw PluginBrokerError.metadata }
    }

    func connect(endpointText: String, token: String, useSavedToken: Bool = false) async throws {
        guard !isBusy else { throw PluginBrokerError.busy }
        guard isForeground else { throw PluginBrokerError.foreground }
        let endpoint = try MCPEndpoint.validated(endpointText)
        let credential = useSavedToken ? try PluginCredentialStore.read(endpoint: endpoint.url.absoluteString) : (token.isEmpty ? nil : token)
        let nextClient = try clientFactory(endpoint, credential)
        disconnect()
        let operation = UUID(); operationID = operation; client = nextClient
        do {
            let server = try await nextClient.initialize()
            try checkOwner(operation)
            guard Self.validInfo(name: server.name, version: server.version) else { throw PluginBrokerError.serverInfo }
            let discovered = try await nextClient.listTools()
            try checkOwner(operation)
            let previous = connections.first { $0.endpoint == endpoint.url.absoluteString }
            stagedConnection = PluginConnectionRecord(id: previous?.id ?? UUID(), endpoint: endpoint.url.absoluteString,
                name: server.name, version: server.version, installedAt: Date(), hasSavedToken: previous?.hasSavedToken ?? false)
            tools = discovered; pendingToken = credential; catalogRevision = UUID(); operationID = nil
        } catch {
            if operationID == operation { disconnect() }
            throw error
        }
    }

    func installConnection(rememberToken: Bool) throws {
        guard !isBusy, isForeground, var connection = stagedConnection, client != nil else { throw PluginBrokerError.notConnected }
        var next = connections.filter { $0.id != connection.id }
        guard next.count < 8 else { throw PluginBrokerError.capacity }
        let writesSecret = rememberToken && pendingToken != nil
        let previousSecret = writesSecret ? try PluginCredentialStore.read(endpoint: connection.endpoint) : nil
        if writesSecret {
            try PluginCredentialStore.save(pendingToken, endpoint: connection.endpoint)
            connection.hasSavedToken = true
        }
        next.append(connection)
        do { try saveConnections(next) }
        catch {
            if writesSecret { try PluginCredentialStore.save(previousSecret, endpoint: connection.endpoint) }
            throw error
        }
        connections = next; activeConnection = connection; stagedConnection = nil; pendingToken = nil
    }

    func prepareReview(toolName: String, argumentText: String) throws -> PluginCallReview {
        invalidateReview()
        guard canReviewTools, let activeConnection,
              let definition = tools.first(where: { $0.name == toolName }) else { throw PluginBrokerError.notConnected }
        let arguments = try MCPJSONValue.parse(Data(argumentText.utf8), maximumBytes: 16_384)
        try definition.inputSchema.validate(arguments)
        let value = try gate.prepare(connectionID: activeConnection.id, catalogRevision: catalogRevision,
            toolName: toolName, arguments: arguments)
        review = value
        return value
    }
    func clearResult() { lastResult = nil }
    func invalidateReview() { gate.invalidate(); review = nil }

    func execute(reviewID: UUID) async throws {
        guard canReviewTools, let connection = activeConnection, let client else { throw PluginBrokerError.notConnected }
        let approved = try gate.consume(id: reviewID, connectionID: connection.id, catalogRevision: catalogRevision)
        review = nil
        // Durable write occurs before network dispatch. No arguments/result body enters this file.
        let record = try journal.begin(connectionID: connection.id, toolName: approved.toolName)
        let operation = UUID(); operationID = operation; activeExecution = record; lastResult = nil
        do {
            let result = try await client.callTool(named: approved.toolName, arguments: approved.arguments)
            try checkOwner(operation)
            try journal.finish(id: record, state: result.isError ? .serverReportedError : .serverReportedSuccess)
            lastResult = result
            operationID = nil; activeExecution = nil
        } catch {
            if operationID == operation {
                // Only the transport can establish that a call was never issued.
                let definite = (error as? MCPClientFailure)?.effectMayHaveOccurred == false
                try? journal.finish(id: record, state: definite ? .localFailure : .unknown)
                operationID = nil; activeExecution = nil
            }
            throw error
        }
    }

    func disconnect() {
        operationID = nil
        invalidateReview()
        if let activeExecution { try? journal.finish(id: activeExecution, state: .unknown) }
        activeExecution = nil
        let previous = client; client = nil
        tools = []; stagedConnection = nil; activeConnection = nil; pendingToken = nil; lastResult = nil
        catalogRevision = UUID()
        if let previous { Task { await previous.cancelCurrentOperation(); await previous.close() } }
    }
    func setForeground(_ value: Bool) { isForeground = value; if !value { disconnect() } }
    func removeConnection(id: UUID) throws {
        guard !isBusy else { throw PluginBrokerError.busy }
        guard let value = connections.first(where: { $0.id == id }) else { return }
        if activeConnection?.id == id || stagedConnection?.id == id { disconnect() }
        try PluginCredentialStore.save(nil, endpoint: value.endpoint)
        let next = connections.filter { $0.id != id }
        try saveConnections(next); connections = next
    }
    private func checkOwner(_ id: UUID) throws {
        try Task.checkCancellation()
        guard operationID == id, isForeground else { throw CancellationError() }
    }
    private func saveConnections(_ values: [PluginConnectionRecord]) throws {
        let data = try JSONEncoder().encode(Snapshot(connections: values))
        guard data.count <= 65_536 else { throw PluginBrokerError.capacity }
        try data.write(to: file, options: [.atomic, .completeFileProtection])
    }
    private static func validInfo(name: String, version: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 256 && version.utf8.count <= 128
            && !(name + version).unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

enum PluginBrokerError: LocalizedError {
    case busy, foreground, notConnected, capacity, metadata, credentials, serverInfo
    var errorDescription: String? {
        switch self {
        case .busy: "Finish or cancel the current plugin operation first."
        case .foreground: "Return to Orivyn and connect again before using a plugin."
        case .notConnected: "Connect, inspect and install this plugin before reviewing a tool call."
        case .capacity: "Orivyn supports eight saved plugin connections. Remove one before installing another."
        case .metadata: "Plugin connections could not be read safely. Existing data was preserved; plugin changes are disabled."
        case .credentials: "The plugin token could not be accessed securely in Keychain. No token is shown or logged."
        case .serverInfo: "The server identity exceeds the supported limits. This connection was not installed."
        }
    }
}
