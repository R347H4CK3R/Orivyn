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
        XCTAssertFalse(prompt.contains("(private)"), "Repository visibility is not an access capability")
        XCTAssertFalse(prompt.contains("No verified guest operating system is integrated"))
    }
    func testToolResultPreservesWholePrerequisitesAndReportsOmissions() throws {
        let capabilities = (0..<8).map { AppSelfKnowledge.Capability(id: "feature-\($0)", status: .conditional,
            detail: String(repeating: "Requires explicit permission. ", count: 12)) }
        let metadata = AppSelfKnowledge(schemaVersion: 1, repository: "https://github.com/R347H4CK3R/Orivyn", repositoryAccess: "Bundled only", capabilities: capabilities)
        let data = try AppSelfKnowledge.toolResult(metadata: metadata, maximumBytes: 1024)
        XCTAssertLessThanOrEqual(data.count, 1024)
        let value = try XCTUnwrap(MCPJSONValue.parse(data).objectValue)
        let retained = try XCTUnwrap(value["capabilities"]?.arrayValue)
        XCTAssertFalse(retained.isEmpty)
        XCTAssertLessThan(retained.count, capabilities.count)
        XCTAssertEqual(value["omittedItems"]?.integerValue, Int64(capabilities.count - retained.count))
        XCTAssertEqual(value["resultTruncated"], .bool(true))
        for (index, item) in retained.enumerated() {
            XCTAssertEqual(item.objectValue?["detail"]?.stringValue, capabilities[index].detail)
            XCTAssertEqual(item.objectValue?["status"]?.stringValue, "conditional")
        }
    }
    func testToolResultRejectsOversizedPrerequisiteRatherThanCuttingIt() {
        let metadata = AppSelfKnowledge(schemaVersion: 1, repository: "https://github.com/R347H4CK3R/Orivyn", repositoryAccess: "Bundled only",
            capabilities: [.init(id: "feature", status: .conditional, detail: String(repeating: "x", count: 1025))])
        XCTAssertThrowsError(try AppSelfKnowledge.toolResult(metadata: metadata, maximumBytes: 4096))
    }
    func testCapabilityDetailsAreOptionalBoundedAndStrict() throws {
        let contract = try LocalCompletionContract.parse(#"{"schema":1,"steps":[{"name":"get_app_info","arguments":{}}]}"#)
        let infoResult = #"{"app":"Orivyn","assistant":"Jarvis","repository":"x","repositoryAccess":"Bundled only","capabilities":[]}"#
        func event(_ action: LocalCompletionContract.Action, _ result: String) -> LocalAgentSnapshot.Event {
            .init(operationID: "test:1", name: action.name, arguments: action.arguments, outcome: "succeeded", result: result)
        }
        for fields in [#"{"id":"voice","status":"conditional"}"#, #"{"id":"voice","status":"conditional","detail":"Needs device permission; not running proof."}"#] {
            let result = infoResult.replacingOccurrences(of: "[]", with: "[" + fields + "]")
            XCTAssertTrue(try LocalCompletionPolicy.derive(contract: contract, history: [event(contract.steps[0], result)]).canAnswer)
        }
        for detail in ["", "bad\u{0}detail", String(repeating: "x", count: 1025)] {
            let fields: MCPJSONValue = .object(["id": .string("voice"), "status": .string("conditional"), "detail": .string(detail)])
            let result = infoResult.replacingOccurrences(of: "[]", with: "[" + String(decoding: try fields.encoded(maximumBytes: 2048), as: UTF8.self) + "]")
            XCTAssertThrowsError(try LocalCompletionPolicy.derive(contract: contract, history: [event(contract.steps[0], result)]))
        }
    }
    func testMissingMetadataDoesNotAdvertiseConditionalTools() {
        let prompt = AppSelfKnowledge.prompt(metadata: nil, version: "unknown", build: "unknown", providerID: "local:test")
        XCTAssertTrue(prompt.contains("metadata is unavailable"))
        XCTAssertFalse(prompt.contains("Inspect private source"))
        XCTAssertTrue(prompt.contains("do not guess"))
    }
}
