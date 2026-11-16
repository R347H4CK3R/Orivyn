import XCTest
@testable import JarvisEVO

final class PluginToolProposalTests: XCTestCase {
    private func catalog() throws -> [MCPToolDefinition] {
        [.init(name: "notes.search", inputSchema: try MCPToolSchema(json: .object([
            "type": .string("object"), "properties": .object(["query": .object(["type": .string("string")])]),
            "required": .array([.string("query")]), "additionalProperties": .bool(false)
        ])))]
    }
    func testExactCatalogCallIsAProposalNotPermission() throws {
        let proposal = try PluginToolProposal.parse(#"{"tool":"notes.search","arguments":{"query":"hello"}}"#, tools: catalog())
        XCTAssertEqual(proposal?.name, "notes.search")
        XCTAssertEqual(proposal?.arguments, .object(["query": .string("hello")]))
    }
    func testGenerationReturnsValidatedProposal() async throws {
        let proposal = try await PluginToolProposal.generate(goal: "find hello", tools: catalog(), provider: ProposalProvider())
        XCTAssertEqual(proposal?.name, "notes.search")
    }
    func testGenerationUsesOnlyVisibleAnswerAfterReasoning() async throws {
        let raw = #"<think>{"tool":"notes.search","arguments":{"query":"hidden"}}</think>{"tool":"notes.search","arguments":{"query":"visible"}}"#
        let provider = ProposalProvider(pieces: raw.map(String.init))
        let result = try await PluginToolProposal.generate(goal: "find visible", tools: catalog(), provider: provider)
        XCTAssertEqual(result?.arguments, .object(["query": .string("visible")]))
    }
    func testUnclosedReasoningCannotBecomeAProposal() async throws {
        let provider = ProposalProvider(pieces: [#"<think>{"tool":"notes.search","arguments":{"query":"hidden"}}"#])
        do {
            _ = try await PluginToolProposal.generate(goal: "find visible", tools: catalog(), provider: provider)
            XCTFail("A hidden-only response must not produce a proposal")
        } catch { }
    }
    func testHiddenOutputStillCountsAgainstReceivedByteLimit() async throws {
        let provider = ProposalProvider(pieces: ["<think>", String(repeating: "x", count: 16_384), "</think>{\"unsupported\":true}"])
        do {
            _ = try await PluginToolProposal.generate(goal: "find visible", tools: catalog(), provider: provider)
            XCTFail("Hidden tokens must not bypass the received byte budget")
        } catch { XCTAssertEqual(error as? MCPClientFailure, MCPClientFailure(.responseTooLarge)) }
    }
    func testUnsupportedHasNoCall() throws {
        XCTAssertNil(try PluginToolProposal.parse(#"{"unsupported":true}"#, tools: catalog()))
    }
    func testUnknownMalformedAndExtraKeysFailClosed() throws {
        for raw in [
            #"{"tool":"shell.run","arguments":{}}"#,
            #"{"tool":"notes.search","arguments":{"command":"rm"}}"#,
            #"{"tool":"notes.search","arguments":{"query":"hello"},"approved":true}"#,
            #"{"tool":"notes.search","tool":"notes.search","arguments":{"query":"hello"}}"#,
            "<think>private</think>{\"unsupported\":true}"
        ] { XCTAssertThrowsError(try PluginToolProposal.parse(raw, tools: catalog())) }
    }
    func testBoundedInputAndEmptyCatalog() throws {
        XCTAssertThrowsError(try PluginToolProposal.prompt(goal: String(repeating: "x", count: 4097), tools: catalog()))
        XCTAssertThrowsError(try PluginToolProposal.prompt(goal: "search", tools: []))
    }
}

private struct ProposalProvider: AIProvider {
    var pieces = [#"{"tool":"notes.search","arguments":{"query":"hello"}}"#]
    let id = "test"
    let displayName = "Test"
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { c in
            for piece in pieces { c.yield(piece) }
            c.finish()
        }
    }
}
