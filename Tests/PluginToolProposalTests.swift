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
    let id = "test"
    let displayName = "Test"
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { c in
            c.yield(#"{"tool":"notes.search","arguments":{"query":"hello"}}"#)
            c.finish()
        }
    }
}
