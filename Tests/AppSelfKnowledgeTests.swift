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
}
