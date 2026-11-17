import XCTest
@testable import JarvisEVO

final class ChatPluginProposalTests: XCTestCase {
    func testProposalDoesNotInvokeFallbackAndUsesOnlyGoalAndCatalog() async throws {
        let recorder = ProposalCapture()
        let provider = ChatPluginProposalProvider(goal: "find hello", tools: try catalog(),
            model: CapturingPluginModel(capture: recorder, output: #"{"tool":"notes.search","arguments":{"query":"hello"}}"#),
            makeFallback: { CapturingPluginModel(capture: recorder, output: "SHOULD NOT RUN") },
            validateContext: {}, publish: { proposal in await recorder.publish(proposal) })
        var output = ""
        for try await text in try await provider.stream(.init(messages: [.init(role: .user, content: "PRIVATE HISTORY")], systemPrompt: "PRIVATE SYSTEM")) { output += text }
        let state = await recorder.snapshot()
        XCTAssertEqual(state.0.count, 1)
        XCTAssertFalse(state.0[0].contains("PRIVATE"))
        XCTAssertEqual(state.1?.name, "notes.search")
        XCTAssertTrue(output.contains("not executed"))
    }
    func testUnsupportedFallsThroughWithoutProposal() async throws {
        let recorder = ProposalCapture()
        let provider = ChatPluginProposalProvider(goal: "write a poem", tools: try catalog(),
            model: CapturingPluginModel(capture: recorder, output: #"{"unsupported":true}"#),
            makeFallback: { CapturingPluginModel(capture: recorder, output: "A poem") }, validateContext: {},
            publish: { value in await recorder.publish(value) })
        var output = ""
        for try await text in try await provider.stream(.init(messages: [], systemPrompt: "")) { output += text }
        XCTAssertEqual(output, "A poem")
        let state = await recorder.snapshot()
        XCTAssertNil(state.1)
        XCTAssertEqual(state.0.count, 2)
    }
    func testInvalidOutputNeverPublishesOrFallsThrough() async throws {
        let recorder = ProposalCapture()
        let provider = ChatPluginProposalProvider(goal: "find hello", tools: try catalog(),
            model: CapturingPluginModel(capture: recorder, output: #"{"tool":"notes.search","arguments":{"query":"hello"},"approved":true}"#),
            makeFallback: { CapturingPluginModel(capture: recorder, output: "BAD") }, validateContext: {},
            publish: { value in await recorder.publish(value) })
        do { for try await _ in try await provider.stream(.init(messages: [], systemPrompt: "")) {} ; XCTFail("Invalid proposal accepted") } catch {}
        let state = await recorder.snapshot()
        XCTAssertEqual(state.0.count, 1); XCTAssertNil(state.1)
    }
    func testDuplicateCatalogNamesRejectedBeforeInference() throws {
        let tool = try catalog()[0]
        XCTAssertThrowsError(try ChatPluginCatalog.validate([tool, tool], goal: "hello"))
    }
    func testStaleContextAfterInferenceCannotPublish() async throws {
        let recorder = ProposalCapture(), checks = ProposalContextChecks()
        let provider = ChatPluginProposalProvider(goal: "find hello", tools: try catalog(),
            model: CapturingPluginModel(capture: recorder, output: #"{"tool":"notes.search","arguments":{"query":"hello"}}"#),
            makeFallback: { CapturingPluginModel(capture: recorder, output: "BAD") },
            validateContext: { try await checks.validate() },
            publish: { value in await recorder.publish(value) })
        do { for try await _ in try await provider.stream(.init(messages: [], systemPrompt: "")) {} ; XCTFail("Stale context accepted") } catch {}
        let state = await recorder.snapshot()
        XCTAssertEqual(state.0.count, 1); XCTAssertNil(state.1)
    }
    func testLeaseRejectsEveryRevisionChangeAndExpiry() throws {
        let request = PluginChatRequest(goal: "find hello", conversation: UUID(), provider: UUID(), connection: UUID(), catalog: UUID())!
        let generation = UUID(), now = Date()
        let value = PendingChatPluginProposal(id: UUID(), proposal: .init(name: "notes.search", arguments: .object([:])),
            request: request, assistantID: UUID(), generationID: generation, createdAt: now)
        func matches(_ c: UUID, _ p: UUID, _ connection: UUID?, _ catalog: UUID, _ g: UUID?, _ time: Date) -> Bool {
            value.isCurrent(conversation: c, provider: p, connection: connection, catalog: catalog, generation: g, now: time)
        }
        XCTAssertTrue(matches(request.conversation, request.provider, request.connection, request.catalog, generation, now))
        XCTAssertFalse(matches(UUID(), request.provider, request.connection, request.catalog, generation, now))
        XCTAssertFalse(matches(request.conversation, UUID(), request.connection, request.catalog, generation, now))
        XCTAssertFalse(matches(request.conversation, request.provider, UUID(), request.catalog, generation, now))
        XCTAssertFalse(matches(request.conversation, request.provider, nil, request.catalog, generation, now))
        XCTAssertFalse(matches(request.conversation, request.provider, request.connection, UUID(), generation, now))
        XCTAssertFalse(matches(request.conversation, request.provider, request.connection, request.catalog, UUID(), now))
        XCTAssertFalse(matches(request.conversation, request.provider, request.connection, request.catalog, generation, now.addingTimeInterval(301)))
        XCTAssertFalse(matches(request.conversation, request.provider, request.connection, request.catalog, generation, now.addingTimeInterval(-1)))
    }
    func testOversizeCatalogRejectedWithoutModelRequest() async throws {
        let recorder = ProposalCapture()
        let provider = ChatPluginProposalProvider(goal: "find hello", tools: Array(repeating: try catalog()[0], count: 65),
            model: CapturingPluginModel(capture: recorder, output: "BAD"), makeFallback: { CapturingPluginModel(capture: recorder, output: "BAD") },
            validateContext: {}, publish: { value in await recorder.publish(value) })
        do { _ = try await provider.stream(.init(messages: [], systemPrompt: "")); XCTFail("Catalog accepted") } catch {}
        let state = await recorder.snapshot(); XCTAssertTrue(state.0.isEmpty); XCTAssertNil(state.1)
    }
    func testCancellationDuringProposalStopsWithoutPublishingOrFallback() async throws {
        let recorder = ProposalCapture()
        let provider = ChatPluginProposalProvider(goal: "find hello", tools: try catalog(),
            model: WaitingPluginModel(capture: recorder),
            makeFallback: { CapturingPluginModel(capture: recorder, output: "BAD") }, validateContext: {},
            publish: { value in await recorder.publish(value) })
        let work = Task {
            for try await _ in try await provider.stream(.init(messages: [], systemPrompt: "")) {}
        }
        for _ in 0..<100 {
            if !(await recorder.snapshot()).0.isEmpty { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let before = await recorder.snapshot()
        XCTAssertEqual(before.0.count, 1)
        work.cancel()
        _ = await work.result
        for _ in 0..<100 {
            if (await recorder.snapshot()).0.contains("cancelled") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let state = await recorder.snapshot()
        XCTAssertEqual(state.0, ["started", "cancelled"])
        XCTAssertNil(state.1)
    }
    func testUnsupportedLazilyStartsFreshFallbackBudget() async throws {
        let recorder = ProposalCapture()
        var expired = NormalChatLocalAgentProvider(turn: NormalChatLocalTurn(goal: "write a poem", hasAttachments: false, isExternalDraft: false)!,
            model: CapturingPluginModel(capture: recorder, output: #"{"type":"answer","text":"A poem"}"#),
            validateContext: {}, read: { _ in throw CancellationError() }, record: { _ in throw CancellationError() })
        expired.deadline = .now.advanced(by: .seconds(-1))
        let baseline = expired
        let provider = ChatPluginProposalProvider(goal: "write a poem", tools: try catalog(),
            model: CapturingPluginModel(capture: recorder, output: #"{"unsupported":true}"#),
            makeFallback: {
                var fresh = baseline
                fresh.deadline = .now.advanced(by: .seconds(120))
                return fresh
            }, validateContext: {}, publish: { _ in throw CancellationError() })
        var output = ""
        for try await token in try await provider.stream(.init(messages: [], systemPrompt: "")) { output += token }
        XCTAssertEqual(output, "A poem")
        let state = await recorder.snapshot(); XCTAssertEqual(state.0.count, 2)
    }
    private func catalog() throws -> [MCPToolDefinition] {
        [.init(name: "notes.search", inputSchema: try MCPToolSchema(json: .object([
            "type": .string("object"), "properties": .object(["query": .object(["type": .string("string")])]),
            "required": .array([.string("query")]), "additionalProperties": .bool(false)])))]
    }
}
private actor ProposalCapture {
    var inputs: [String] = []; var proposed: PluginToolProposal?
    func add(_ value: String) { inputs.append(value) }
    func publish(_ value: PluginToolProposal) { proposed = value }
    func snapshot() -> ([String], PluginToolProposal?) { (inputs, proposed) }
}
private struct CapturingPluginModel: AIProvider {
    let id = "fixture"; let displayName = "fixture"
    let capture: ProposalCapture; let output: String
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        await capture.add(request.systemPrompt + request.messages.map(\.content).joined())
        let visible = request.normalChatAnswer ? "A poem" : output
        return AsyncThrowingStream { $0.yield(visible); $0.finish() }
    }
}

private actor ProposalContextChecks {
    var count = 0
    func validate() throws { count += 1; if count > 1 { throw CancellationError() } }
}

private struct WaitingPluginModel: AIProvider {
    let id = "waiting"; let displayName = "Waiting"; let capture: ProposalCapture
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        await capture.add("started")
        do { try await Task.sleep(for: .seconds(60)) }
        catch { await capture.add("cancelled"); throw error }
        return AsyncThrowingStream { $0.finish() }
    }
}
