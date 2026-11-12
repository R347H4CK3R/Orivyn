import XCTest
@testable import JarvisEVO

final class AppSelfKnowledgeTests: XCTestCase {
    func testBundledKnowledgeLoadsWithoutPrivateSource() throws {
        let value = try XCTUnwrap(AppSelfKnowledge.load())
        XCTAssertEqual(value.schemaVersion, 1)
        XCTAssertEqual(value.repository, "https://github.com/R347H4CK3R/Orivyn")
        XCTAssertTrue(value.repositoryAccess.contains("not source code"))
        XCTAssertEqual(value.capabilities.first { $0.id == "self-repair" }?.status, .notAvailable)
    }
    func testRuntimeIdentityAndProviderAreIncludedWithoutFabricatedVersion() {
        let text = AppSelfKnowledge.prompt(bundle: Bundle(for: Self.self), providerID: "local:test")
        XCTAssertTrue(text.contains("local:test"))
        XCTAssertTrue(text.contains("Build:"))
        XCTAssertFalse(text.contains("release complete"))
    }
    func testInvalidSchemaAndOversizedDataFailClosed() {
        XCTAssertNil(AppSelfKnowledge.decode(Data("{}".utf8)))
        XCTAssertNil(AppSelfKnowledge.decode(Data(repeating: 32, count: 12001)))
        let invalid = """
        {"schemaVersion":2,"repository":"https://github.com/R347H4CK3R/Orivyn","repositoryAccess":"private","capabilities":[]}
        """
        XCTAssertNil(AppSelfKnowledge.decode(Data(invalid.utf8)))
    }
    func testRealLocalModelAcceptsKnowledgeAtProductionOutputReservation() async throws {
        let model = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "qwen2.5-0.5b-instruct-q4_k_m", withExtension: "gguf"))
        let engine = LlamaEngine()
        let request = GenerationRequest(messages: [ChatMessage(role: .user,
            content: "What is the name of this app? Answer with just the name.")],
            systemPrompt: AppSelfKnowledge.prompt(providerID: "local:qwen"), maxTokens: 1024, temperature: 0)
        do {
            let stream = try await engine.stream(request, modelURL: model)
            var output = ""
            for try await chunk in stream { output += chunk }
            XCTAssertTrue(output.localizedCaseInsensitiveContains("Orivyn"), "Actual knowledge response: \(output)")
            await engine.unload()
        } catch {
            await engine.unload()
            throw error
        }
    }

}
