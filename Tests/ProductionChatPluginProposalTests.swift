import XCTest
import Foundation
@testable import JarvisEVO

/// Real pinned local inference; no scripted decisions, execution or retries.
@MainActor
final class ProductionChatPluginProposalTests: XCTestCase {
    func testPinnedModelSelectsExactPluginProposalWithoutPrivateContextOrExecution() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ORIVYN_REQUIRE_NORMAL_CHAT_MODEL"] == "1" else {
            throw XCTSkip("Required model fixture is not enabled; no actual-model pass is claimed.")
        }
        #if !targetEnvironment(simulator)
        XCTFail("Required proposal-model acceptance needs the iOS simulator.")
        #else
        executionTimeAllowance = 240
        guard let path = environment["ORIVYN_CONVERSATION_MODEL_DIR"], path.hasPrefix("/"), path != "/",
              !path.utf8.contains(0) else { XCTFail("Dedicated model fixture directory required"); return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { XCTFail("Regular fixture directory required"); return }
        let descriptor = try ProductionModelFixture.descriptor(environment: environment)
        guard descriptor.id == "qwen3-1.7b-q4_k_m" else { XCTFail("Only pinned Q4 fixture admitted"); return }
        let lock = directory.appendingPathComponent(".production-local-agent-test-lock", isDirectory: true)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: lock) }

        let query = "amber atlas " + UUID().uuidString.lowercased()
        let goal = "Search my connected notes for the exact phrase \"\(query)\". Do not create or change any note."
        let tools = try [
            MCPToolDefinition(name: "notes.search", inputSchema: schema(property: "query")),
            MCPToolDefinition(name: "notes.create", inputSchema: schema(property: "body"))
        ]
        let privateHistory = "PRIVATE_HISTORY_" + UUID().uuidString
        let privateSystem = "PRIVATE_SYSTEM_" + UUID().uuidString
        let observation = PluginModelObservation()
        let actualModel = LocalAIProvider(store: try LocalModelStore(root: directory), model: descriptor)
        let provider = ChatPluginProposalProvider(goal: goal, tools: tools,
            model: ObservedPluginModel(actual: actualModel, observation: observation),
            makeFallback: { ForbiddenProposalFallback(observation: observation) },
            validateContext: { try Task.checkCancellation() },
            publish: { proposal in await observation.publish(proposal) })
        var output = "", streamError: (any Error)?
        do {
            for try await token in try await provider.stream(.init(
                messages: [.init(role: .user, content: privateHistory)], systemPrompt: privateSystem)) {
                try Task.checkCancellation()
                output += token
                guard output.utf8.count <= 32_768 else { throw LocalAgentError.outputBound }
            }
            try Task.checkCancellation()
        } catch { streamError = error }
        await observation.cancelAndJoin()
        await actualModel.unload()
        let evidence = await observation.snapshot()
        let proposed = try evidence.proposals.map { proposal in
            String(decoding: try MCPJSONValue.object(["tool": .string(proposal.name), "arguments": proposal.arguments]).encoded(maximumBytes: 16_384), as: UTF8.self)
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: "scope=real pinned local model, synthetic catalog and goal, proposal only; not broker/UI/device proof\nmodelSHA256=\(descriptor.sha256)\nquery=\(query)\nerror=\(String(describing: streamError))\nrequests=\(evidence.requests.joined(separator: "\n---\n"))\nproposals=\(proposed)\nfallback=\(evidence.fallback)\nmodelOutputBytes=\(evidence.outputBytes)\nmodelOutputTruncated=\(evidence.outputTruncated)\nvisibleModelOutput=\(evidence.visibleOutput)\noutput=\(output)")
        attachment.name = "real-model-connected-plugin-proposal"
        attachment.lifetime = .keepAlways
        add(attachment)
        try Task.checkCancellation()
        if let streamError { throw streamError }
        XCTAssertEqual(evidence.requests.count, 1, "Exactly one actual local-model decision, no retries")
        let request = try XCTUnwrap(evidence.requests.first)
        XCTAssertTrue(request.contains(query))
        XCTAssertTrue(request.contains("notes.search"))
        XCTAssertTrue(request.contains("notes.create"))
        XCTAssertFalse(request.contains(privateHistory))
        XCTAssertFalse(request.contains(privateSystem))
        XCTAssertFalse(evidence.fallback, "Unsupported is not a successful proposal")
        XCTAssertEqual(evidence.proposals.count, 1)
        let proposal = try XCTUnwrap(evidence.proposals.first)
        XCTAssertEqual(proposal.name, "notes.search")
        let arguments = try XCTUnwrap(proposal.arguments.objectValue)
        XCTAssertEqual(Set(arguments.keys), ["query"])
        let proposedQuery = try XCTUnwrap(arguments["query"]?.stringValue)
        XCTAssertTrue(proposedQuery.utf8.elementsEqual(query.utf8), "Model must copy only the requested exact search phrase")
        XCTAssertNoThrow(try tools[0].inputSchema.validate(proposal.arguments))
        XCTAssertTrue(output.contains("not executed"))
        XCTAssertTrue(output.contains("Review the exact destination and arguments"))
        XCTAssertFalse(output.contains("<think>"))
        // No PluginBroker, MCPClient or remote provider is supplied to this test.
        // It validates the proposal adapter, not real external execution safety.
        #endif
    }

    private func schema(property: String) throws -> MCPToolSchema {
        try MCPToolSchema(json: .object([
            "type": .string("object"),
            "properties": .object([property: .object(["type": .string("string")])]),
            "required": .array([.string(property)]), "additionalProperties": .bool(false)
        ]))
    }
}

private struct ObservedPluginModel: AIProvider {
    let actual: LocalAIProvider
    let observation: PluginModelObservation
    var id: String { actual.id }
    var displayName: String { actual.displayName }
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        await observation.request(request.systemPrompt + request.messages.map(\.content).joined(separator: "\n"))
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task {
            do {
                for try await token in try await actual.stream(request) {
                    try Task.checkCancellation()
                    await observation.observeOutput(token)
                    pair.continuation.yield(token)
                }
                pair.continuation.finish()
            } catch { pair.continuation.finish(throwing: error) }
        }
        await observation.bind(task)
        pair.continuation.onTermination = { _ in task.cancel() }
        return pair.stream
    }
}
private struct ForbiddenProposalFallback: AIProvider {
    let id = "forbidden-test-fallback", displayName = "Failure sentinel"
    let observation: PluginModelObservation
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        await observation.markFallback()
        throw LocalAgentError.invalidState
    }
}
private actor PluginModelObservation {
    var requests: [String] = []
    var proposals: [PluginToolProposal] = []
    var fallback = false
    var visibleOutput = ""
    private var filter = ChatAnswerStream()
    private var worker: Task<Void, Never>?
    var outputBytes = 0
    var outputTruncated = false
    func request(_ text: String) { requests.append(text) }
    func publish(_ proposal: PluginToolProposal) { proposals.append(proposal) }
    func markFallback() { fallback = true }
    func observeOutput(_ token: String) {
        outputBytes += token.utf8.count
        let visible = filter.append(token)
        if !outputTruncated, visibleOutput.utf8.count + visible.utf8.count <= 16_384 { visibleOutput += visible }
        else { outputTruncated = true }
    }
    func bind(_ task: Task<Void, Never>) { worker = task }
    func cancelAndJoin() async {
        let task = worker
        task?.cancel()
        await task?.value
        worker = nil
    }
    func snapshot() -> (requests: [String], proposals: [PluginToolProposal], fallback: Bool, visibleOutput: String, outputBytes: Int, outputTruncated: Bool) {
        (requests, proposals, fallback, visibleOutput, outputBytes, outputTruncated)
    }
}
