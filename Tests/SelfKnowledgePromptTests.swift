import XCTest
@testable import JarvisEVO

final class SelfKnowledgePromptTests: XCTestCase {
    func testPromptDistinguishesReviewedSourceInspectionFromChatSelfRepair() throws {
        let data = Data(#"{"schemaVersion":1,"repository":"https://github.com/R347H4CK3R/Orivyn","repositoryAccess":"metadata, not source code","capabilities":[{"id":"self-repair","status":"notAvailable","detail":"No executable changes"}]}"#.utf8)
        let value = try XCTUnwrap(AppSelfKnowledge.decode(data))
        let prompt = AppSelfKnowledge.prompt(metadata: value, version: "test", build: "42", providerID: "local:test")
        XCTAssertTrue(prompt.contains("Inspect private source"))
        XCTAssertTrue(prompt.contains("explicit authorization"))
        XCTAssertTrue(prompt.contains("Chat cannot inspect"))
        XCTAssertTrue(prompt.contains("self-repair [notAvailable]"))
        XCTAssertTrue(prompt.contains("unverified on iPhone"))
        XCTAssertTrue(prompt.contains("Build: 42"))
        XCTAssertFalse(prompt.contains("No verified guest operating system is integrated"))
    }
    func testMissingMetadataDoesNotAdvertiseConditionalTools() {
        let prompt = AppSelfKnowledge.prompt(metadata: nil, version: "unknown", build: "unknown", providerID: "local:test")
        XCTAssertTrue(prompt.contains("metadata is unavailable"))
        XCTAssertFalse(prompt.contains("Inspect private source"))
        XCTAssertTrue(prompt.contains("do not guess"))
    }
}
