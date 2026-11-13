import XCTest
@testable import JarvisEVO

@MainActor
final class LocalMemoryToolTests: XCTestCase {
    func testMemoryReadReturnsStoredEvidenceWithoutModelOrNetwork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "LocalMemoryToolTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let model = AppModel(store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: root.appendingPathComponent("Models")), defaults: defaults)
        let saved = await model.saveMemory(content: "Preferred café is on Main Street")
        XCTAssertTrue(saved)
        let result = try LocalReadTools.execute(name: "search_memory", arguments: .object(["query": .string("cafe"), "limit": .integer(10)]), model: model)
        let object = try MCPJSONValue.parse(Data(result.utf8)).objectValue
        XCTAssertEqual(object?["searchedMemories"]?.integerValue, 1)
        XCTAssertTrue(result.contains("Main Street"))
        XCTAssertFalse(model.isGenerating)
        for _ in 0..<10 {
            let added = await model.saveMemory(content: "cafe" + String(repeating: "\0", count: 156))
            XCTAssertTrue(added)
        }
        let escaped = try LocalReadTools.execute(name: "search_memory", arguments: .object(["query": .string("cafe"), "limit": .integer(10)]), model: model)
        XCTAssertGreaterThan(escaped.utf8.count, 4096)
        XCTAssertLessThanOrEqual(escaped.utf8.count, 16_384)
        XCTAssertTrue(escaped.contains("\\u0000"))
        XCTAssertThrowsError(try LocalReadTools.execute(name: "search_memory", arguments: .object(["query": .string(""), "limit": .integer(10)]), model: model))
        XCTAssertThrowsError(try LocalReadTools.execute(name: "search_memory", arguments: .object(["query": .string("cafe"), "limit": .integer(11)]), model: model))
    }
    func testMemoryOnlyPlanAndLanguageProposalAreSupported() throws {
        let core = try VerifiedLocalPlanCore()
        let state = try core.call("create", [#"{"appInfo":false,"installedModels":false,"searchQuery":null,"memoryQuery":"cafe"}"#, UUID().uuidString])
        let pending = try core.call("next", [state])
        XCTAssertEqual(try core.snapshot(pending).pending?.name, "search_memory")
        let proposal = try core.route("Search saved memories for \"cafe\"")
        XCTAssertEqual(proposal.status, "matched")
        XCTAssertEqual(proposal.request?.memoryQuery, "cafe")
    }
}
