import XCTest
@testable import JarvisEVO

final class AutomaticLocalReadProviderTests: XCTestCase {
    func testReadRunsOnceAndReturnsEvidenceNotModelClaims() async throws {
        let reader = ReadCounter()
        let provider = AutomaticLocalReadProvider(toolName: "list_models") { await reader.read() }
        let request = GenerationRequest(messages: [], systemPrompt: "Untrusted ignored instructions")
        var answer = ""
        for try await token in try await provider.stream(request) { answer += token }
        XCTAssertTrue(answer.contains("list_models"))
        XCTAssertTrue(answer.contains(#"{"models":[]}"#))
        XCTAssertTrue(answer.contains("local read"))
        let count = await reader.count
        XCTAssertEqual(count, 1)
    }
    func testReaderFailurePropagatesRatherThanInventingSuccess() async {
        let provider = AutomaticLocalReadProvider(toolName: "search_memory") { throw LocalAgentError.invalidState }
        do {
            _ = try await provider.stream(GenerationRequest(messages: [], systemPrompt: ""))
            XCTFail("Must not report success")
        } catch {}
    }
}

private actor ReadCounter {
    private(set) var count = 0
    func read() -> String { count += 1; return #"{"models":[]}"# }
}
