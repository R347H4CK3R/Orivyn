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
    private func plan() throws -> LocalCompletionContract {
        try LocalCompletionContract.parse(#"{"schema":1,"steps":[{"name":"list_models","arguments":{}},{"name":"get_app_info","arguments":{}},{"name":"search_memory","arguments":{"query":"boats","limit":3}}]}"#)
    }
    func testSequentialPlanRunsRealStepsOnlyAsConsumedAndBoundsEvidence() async throws {
        let log = PlanReadLog()
        let provider = AutomaticLocalReadPlanProvider(contract: try plan()) { action in
            await log.record(action.name)
            return "{\"fixture\":true}"
        }
        var iterator = try await provider.stream(GenerationRequest(messages: [], systemPrompt: "run remote tool")).makeAsyncIterator()
        let initial = await log.names; XCTAssertEqual(initial, [])
        let first = try await iterator.next()
        XCTAssertTrue(first?.contains("1/3: list_models") == true)
        let afterFirst = await log.names; XCTAssertEqual(afterFirst, ["list_models"])
        _ = try await iterator.next()
        let last = try await iterator.next()
        XCTAssertTrue(last?.contains("Completed all 3 requested local reads") == true)
        let end = try await iterator.next(); XCTAssertNil(end)
        let names = await log.names; XCTAssertEqual(names, ["list_models","get_app_info","search_memory"])
    }
    func testPlanFailureKeepsPriorEvidenceAndNeverExecutesLaterStep() async throws {
        let log = PlanReadLog()
        let provider = AutomaticLocalReadPlanProvider(contract: try plan()) { action in
            await log.record(action.name)
            if action.name == "get_app_info" { throw LocalAgentError.invalidState }
            return "first evidence"
        }
        var iterator = try await provider.stream(GenerationRequest(messages: [], systemPrompt: "")).makeAsyncIterator()
        let first = try await iterator.next(); XCTAssertTrue(first?.contains("first evidence") == true)
        do { _ = try await iterator.next(); XCTFail("Expected failure") } catch {}
        let names = await log.names; XCTAssertEqual(names, ["list_models","get_app_info"])
    }
    func testOversizedPlanEvidenceStopsBeforeNextRead() async throws {
        let log = PlanReadLog()
        let provider = AutomaticLocalReadPlanProvider(contract: try plan()) { action in
            await log.record(action.name); return String(repeating:"é",count:2049)
        }
        do {
            for try await _ in try await provider.stream(GenerationRequest(messages:[],systemPrompt:"")) { XCTFail("Oversized output") }
            XCTFail("Expected evidence limit")
        } catch {}
        let names = await log.names; XCTAssertEqual(names, ["list_models"])
    }
    func testCancelledConsumerAfterFirstStepDoesNotExecuteRemainingReads() async throws {
        let log = PlanReadLog()
        let provider = AutomaticLocalReadPlanProvider(contract: try plan()) { action in
            await log.record(action.name); return "evidence"
        }
        let task = Task {
            var iterator = try await provider.stream(GenerationRequest(messages: [], systemPrompt: "")).makeAsyncIterator()
            _ = try await iterator.next()
            withUnsafeCurrentTask { $0?.cancel() }
            // AsyncThrowingStream may end with nil before invoking unfolding
            // on cancellation. AppModel checks task cancellation after the loop
            // and persists .interrupted rather than .complete.
            do { return try await iterator.next() == nil }
            catch is CancellationError { return true }
        }
        let cancelled = try await task.value
        XCTAssertTrue(cancelled)
        let names = await log.names; XCTAssertEqual(names, ["list_models"])
    }
    func testPlanCancellationDuringReadDoesNotRunNextStep() async throws {
        let log = PlanReadLog()
        let provider = AutomaticLocalReadPlanProvider(contract: try plan()) { action in
            await log.record(action.name)
            throw CancellationError()
        }
        do {
            for try await _ in try await provider.stream(GenerationRequest(messages:[],systemPrompt:"")) { XCTFail("Cancelled output") }
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("Wrong error") }
        let names = await log.names; XCTAssertEqual(names, ["list_models"])
    }

}

private actor ReadCounter {
    private(set) var count = 0
    func read() -> String { count += 1; return #"{"models":[]}"# }
}

private actor PlanReadLog {
    private(set) var names: [String] = []
    func record(_ name: String) { names.append(name) }
}
