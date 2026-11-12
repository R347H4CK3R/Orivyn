import XCTest
@testable import JarvisEVO

final class LocalResourceReleaseTests: XCTestCase {
    /// Real model, no synthetic inference. Removing the awaited release makes the
    /// second stream fail busy while the first worker still owns its resources.
    func testUnloadWaitsForActiveWorkerBeforeRealModelReload() async throws {
        let url = try XCTUnwrap(Bundle(for: LocalResourceReleaseTests.self)
            .url(forResource: "qwen2.5-0.5b-instruct-q4_k_m", withExtension: "gguf"),
            "This gate requires the pinned, bundled real model")
        let engine = LlamaEngine()
        let longRequest = GenerationRequest(messages: [ChatMessage(role: .user,
            content: "Count from 1 to 1000, with each number on a new line. Continue counting without explanation.")],
            systemPrompt: "Follow the instruction.", maxTokens: 1024, temperature: 0)
        let first = try await engine.stream(longRequest, modelURL: url)
        var iterator = first.makeAsyncIterator()
        let token = try await iterator.next()
        XCTAssertNotNil(token, "The actual worker must have loaded and generated before release")
        await engine.unload()
        let request = GenerationRequest(messages: [ChatMessage(role: .user, content: "Say hello.")],
            systemPrompt: "Be brief.", maxTokens: 24, temperature: 0)
        do {
            let second = try await engine.stream(request, modelURL: url)
            var output = ""
            for try await chunk in second { output += chunk }
            XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } catch {
            XCTFail("unload() returned before the active engine was reusable: \(error)")
        }
        await engine.unload()
    }
}
