import XCTest
@testable import JarvisEVO

@MainActor
final class PluginBrokerTests: XCTestCase {
    private var root: URL!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func testConnectDiscoversButDoesNotInstallOrRunAnything() async throws {
        let client = ControlledPluginClient()
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        XCTAssertEqual(broker.tools.map(\.name), ["workspace.write"])
        XCTAssertNotNil(broker.stagedConnection); XCTAssertTrue(broker.connections.isEmpty)
        XCTAssertTrue(broker.journal.records.isEmpty)
        let calls = await client.calls; XCTAssertEqual(calls, 0)
        XCTAssertThrowsError(try broker.prepareReview(toolName: "workspace.write", argumentText: "{}"))
    }

    func testExplicitInstallAndReviewStillDoNotExecuteUntilRun() async throws {
        let client = ControlledPluginClient()
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let review = try broker.prepareReview(toolName: "workspace.write", argumentText: "{\"text\":\"Only approved text\"}")
        let before = await client.calls; XCTAssertEqual(before, 0)
        XCTAssertTrue(broker.journal.records.isEmpty)
        try await broker.execute(reviewID: review.id)
        let after = await client.calls; XCTAssertEqual(after, 1)
        let arguments = await client.lastArguments
        XCTAssertEqual(arguments, .object(["text": .string("Only approved text")]))
        XCTAssertEqual(broker.journal.records.first?.state, .serverReportedSuccess)
        XCTAssertNotNil(broker.lastResult)
        do { try await broker.execute(reviewID: review.id); XCTFail("Review must be consumed") } catch { }
        let final = await client.calls; XCTAssertEqual(final, 1)
    }

    func testInvalidArgumentsNeverCreateExecutionRecordOrCallServer() async throws {
        let client = ControlledPluginClient()
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        for input in ["{bad", "[]", "{\"extra\":1}", "{\"text\":true}"] {
            XCTAssertThrowsError(try broker.prepareReview(toolName: "workspace.write", argumentText: input))
        }
        XCTAssertTrue(broker.journal.records.isEmpty)
        let calls = await client.calls; XCTAssertEqual(calls, 0)
    }

    func testBackgroundInvalidatesReviewAndClearsLiveSessionWithoutDeletingSavedMetadata() async throws {
        let client = ControlledPluginClient()
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let review = try broker.prepareReview(toolName: "workspace.write", argumentText: "{}")
        broker.setForeground(false)
        XCTAssertTrue(broker.tools.isEmpty); XCTAssertNil(broker.review)
        XCTAssertEqual(broker.connections.count, 1)
        do { try await broker.execute(reviewID: review.id); XCTFail("Background execution forbidden") } catch { }
        let calls = await client.calls; XCTAssertEqual(calls, 0)
    }

    func testRelaunchDoesNotReconnectOrReplaySavedConnection() async throws {
        let client = ControlledPluginClient()
        let factory: @MainActor (MCPEndpoint, String?) throws -> any PluginMCPClient = { _, _ in client }
        let broker = try PluginBroker(directory: root, clientFactory: factory)
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let reopened = try PluginBroker(directory: root, clientFactory: factory)
        XCTAssertEqual(reopened.connections.count, 1); XCTAssertTrue(reopened.tools.isEmpty)
        XCTAssertNil(reopened.stagedConnection); XCTAssertNil(reopened.lastResult)
        let initializes = await client.initializes; XCTAssertEqual(initializes, 1)
    }

    func testUncertainCallIsRecordedUnknownAndNotRetried() async throws {
        let client = ControlledPluginClient(failure: MCPClientFailure(.timedOut, effectMayHaveOccurred: true))
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let review = try broker.prepareReview(toolName: "workspace.write", argumentText: "{}")
        do { try await broker.execute(reviewID: review.id); XCTFail("Expected uncertainty") } catch { }
        XCTAssertEqual(broker.journal.records.first?.state, .unknown)
        XCTAssertNil(broker.lastResult); XCTAssertNil(broker.completedResult)
        let calls = await client.calls; XCTAssertEqual(calls, 1)
    }

    func testJournalFailureStopsDispatchBeforeNetworkCall() async throws {
        let client = ControlledPluginClient()
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let review = try broker.prepareReview(toolName: "workspace.write", argumentText: "{}")
        try FileManager.default.removeItem(at: root)
        try Data("not a directory".utf8).write(to: root)
        do { try await broker.execute(reviewID: review.id); XCTFail("No durable record") } catch { }
        let calls = await client.calls; XCTAssertEqual(calls, 0)
    }

    func testPreCancelledConnectNeverCreatesClientOrInitializes() async throws {
        let client = ControlledPluginClient()
        var creations = 0
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in creations += 1; return client })
        let task = Task { try await broker.connect(endpointText: "https://example.invalid/mcp", token: "") }
        task.cancel()
        do { try await task.value; XCTFail("Canceled form must not connect") } catch { }
        XCTAssertEqual(creations, 0)
        let initializes = await client.initializes; XCTAssertEqual(initializes, 0)
        XCTAssertNil(broker.stagedConnection)
    }

    func testDisconnectWhileInitializingCannotRestoreStagedConnection() async throws {
        let client = ControlledPluginClient(suspendInitialization: true)
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        let task = Task { try await broker.connect(endpointText: "https://example.invalid/mcp", token: "") }
        try await waitUntil { await client.initializationIsSuspended }
        broker.disconnect()
        await client.releaseInitialization()
        do { try await task.value; XCTFail("Late handshake must be discarded") } catch { }
        XCTAssertFalse(broker.isBusy); XCTAssertNil(broker.stagedConnection)
        XCTAssertTrue(broker.tools.isEmpty); XCTAssertTrue(broker.connections.isEmpty)
    }

    func testLateOldHandshakeCannotOverwriteNewConnection() async throws {
        let old = ControlledPluginClient(suspendInitialization: true)
        let new = ControlledPluginClient()
        let broker = try PluginBroker(directory: root, clientFactory: { endpoint, _ in
            endpoint.url.host == "old.invalid" ? old : new
        })
        let task = Task { try await broker.connect(endpointText: "https://old.invalid/mcp", token: "") }
        try await waitUntil { await old.initializationIsSuspended }
        broker.disconnect()
        try await broker.connect(endpointText: "https://new.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        await old.releaseInitialization()
        do { try await task.value; XCTFail("Old handshake must lose ownership") } catch { }
        XCTAssertEqual(broker.activeConnection?.endpoint, "https://new.invalid/mcp")
        XCTAssertTrue(broker.canReviewTools)
    }

    func testBackgroundDuringCallKeepsUnknownDespiteLateSuccess() async throws {
        let client = ControlledPluginClient(suspendCall: true)
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let review = try broker.prepareReview(toolName: "workspace.write", argumentText: "{}")
        let task = Task { try await broker.execute(reviewID: review.id) }
        try await waitUntil { await client.callIsSuspended }
        XCTAssertEqual(broker.journal.records.first?.state, .running)
        broker.setForeground(false)
        XCTAssertEqual(broker.journal.records.first?.state, .unknown)
        await client.releaseCall()
        do { try await task.value; XCTFail("Late success must not replace unknown") } catch { }
        XCTAssertEqual(broker.journal.records.first?.state, .unknown)
        XCTAssertNil(broker.lastResult); XCTAssertNil(broker.completedResult); XCTAssertFalse(broker.isBusy)
        let calls = await client.calls; XCTAssertEqual(calls, 1)
    }

    func testPreCancelledRunCannotWriteRecordOrDispatch() async throws {
        let client = ControlledPluginClient()
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let review = try broker.prepareReview(toolName: "workspace.write", argumentText: "{}")
        let task = Task { try await broker.execute(reviewID: review.id) }
        task.cancel()
        do { try await task.value; XCTFail("Canceled call must not dispatch") } catch { }
        XCTAssertTrue(broker.journal.records.isEmpty)
        let calls = await client.calls; XCTAssertEqual(calls, 0)
    }

    func testOutcomeWriteFailureBlocksFurtherCallsInsteadOfShowingRunning() async throws {
        let client = ControlledPluginClient(suspendCall: true)
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let review = try broker.prepareReview(toolName: "workspace.write", argumentText: "{}")
        let task = Task { try await broker.execute(reviewID: review.id) }
        try await waitUntil { await client.callIsSuspended }
        let journalFile = root.appendingPathComponent("plugin-executions.json")
        let durableBefore = try Data(contentsOf: journalFile)
        // A nonempty directory at the destination reliably prevents atomic replacement,
        // without changing global permissions or relying on the simulator's UID.
        try FileManager.default.removeItem(at: journalFile)
        try FileManager.default.createDirectory(at: journalFile, withIntermediateDirectories: false)
        try durableBefore.write(to: journalFile.appendingPathComponent("preserved-running.json"))
        await client.releaseCall()
        do { try await task.value; XCTFail("Outcome could not be committed") } catch { }
        XCTAssertEqual(broker.journal.records.first?.state, .unknown)
        XCTAssertFalse(broker.canReviewTools)
        XCTAssertFalse(broker.isBusy)
        XCTAssertEqual(try Data(contentsOf: journalFile.appendingPathComponent("preserved-running.json")), durableBefore)
        let calls = await client.calls; XCTAssertEqual(calls, 1)
    }

    func testCompletedResultRequiresSameConversationAndAppendsWithoutReplay() async throws {
        let client = ControlledPluginClient()
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let context = UUID()
        let review = try broker.prepareReview(toolName: "workspace.write", argumentText: "{}")
        try await broker.execute(reviewID: review.id, conversationContext: context)
        let result = try XCTUnwrap(broker.completedResult)
        XCTAssertThrowsError(try broker.consumeResultDraft(executionID: result.executionID, conversationContext: UUID(), currentDraft: "preserve"))
        XCTAssertNotNil(broker.completedResult)
        let draft = try broker.consumeResultDraft(executionID: result.executionID, conversationContext: context, currentDraft: "preserve")
        XCTAssertTrue(draft.hasPrefix("preserve\n\n"))
        XCTAssertTrue(draft.contains("not independently verified"))
        XCTAssertThrowsError(try broker.consumeResultDraft(executionID: result.executionID, conversationContext: context, currentDraft: draft))
        let calls = await client.calls; XCTAssertEqual(calls, 1)
    }
    func testDisconnectInvalidatesCompletedHandoffAndResultIsNotPersisted() async throws {
        let client = ControlledPluginClient()
        let broker = try PluginBroker(directory: root, clientFactory: { _, _ in client })
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let context = UUID(), review = try broker.prepareReview(toolName: "workspace.write", argumentText: "{}")
        try await broker.execute(reviewID: review.id, conversationContext: context)
        let result = try XCTUnwrap(broker.completedResult)
        broker.disconnect()
        XCTAssertThrowsError(try broker.consumeResultDraft(executionID: result.executionID, conversationContext: context, currentDraft: "keep"))
        XCTAssertNil(try PluginBroker(directory: root).completedResult)
        let log = try String(contentsOf: root.appendingPathComponent("plugin-executions.json"), encoding: .utf8)
        XCTAssertFalse(log.contains("Server-reported result; not independent proof"))
    }

    private func waitUntil(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Controlled operation never reached its suspension point")
        throw CancellationError()
    }
}

private actor ControlledPluginClient: PluginMCPClient {
    private(set) var calls = 0
    private(set) var initializes = 0
    private(set) var lastArguments: MCPJSONValue?
    let failure: MCPClientFailure?
    let suspendInitialization: Bool
    let suspendCall: Bool
    private var initializationContinuation: CheckedContinuation<Void, Never>?
    private var callContinuation: CheckedContinuation<Void, Never>?
    var initializationIsSuspended: Bool { initializationContinuation != nil }
    var callIsSuspended: Bool { callContinuation != nil }
    init(failure: MCPClientFailure? = nil, suspendInitialization: Bool = false, suspendCall: Bool = false) {
        self.failure = failure; self.suspendInitialization = suspendInitialization; self.suspendCall = suspendCall
    }
    func initialize() async throws -> MCPServerInfo {
        initializes += 1
        if suspendInitialization { await withCheckedContinuation { initializationContinuation = $0 } }
        return MCPServerInfo(name: "Test boundary", version: "1")
    }
    func releaseInitialization() { initializationContinuation?.resume(); initializationContinuation = nil }
    func releaseCall() { callContinuation?.resume(); callContinuation = nil }
    func listTools() async throws -> [MCPToolDefinition] {
        let schema = try MCPToolSchema(json: .object([
            "type": .string("object"), "properties": .object(["text": .object(["type": .string("string")])]),
            "additionalProperties": .bool(false)
        ]))
        return [MCPToolDefinition(name: "workspace.write", inputSchema: schema)]
    }
    func callTool(named: String, arguments: MCPJSONValue) async throws -> MCPToolCallResult {
        calls += 1; lastArguments = arguments
        if suspendCall { await withCheckedContinuation { callContinuation = $0 } }
        if let failure { throw failure }
        return MCPToolCallResult(content: [.text("Server-reported result; not independent proof")], structuredContent: nil, isError: false)
    }
    func cancelCurrentOperation() async { }
    func close() async { }
}
