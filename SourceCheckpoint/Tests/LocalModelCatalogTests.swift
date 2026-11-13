import XCTest
@testable import JarvisEVO
final class LocalModelCatalogTests: XCTestCase {
    func testPurposeSearchIsCaseInsensitiveAndTrimsWhitespace() {
        let result = LocalModelCatalog.filtered(query: " CODING ", purpose: "All", smallestFirst: false)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.allSatisfy { $0.purpose == "Coding" })
        XCTAssertTrue(LocalModelCatalog.filtered(query: "missing model", purpose: "All", smallestFirst: false).isEmpty)
    }
    func testPurposeAndQueryCombineWithoutChangingDefault() {
        let result = LocalModelCatalog.filtered(query: "1.5B", purpose: "Coding", smallestFirst: false)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.allSatisfy { $0.purpose == "Coding" && $0.baseModel.contains("1.5B") })
        XCTAssertEqual(LocalModelCatalog.defaultModel.id, "qwen2.5-0.5b-instruct-q4_k_m")
        XCTAssertEqual(LocalModelCatalog.defaultModel.sha256, "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db")
    }
    func testSizeOrderAndStorageRAMBoundaries() {
        let result = LocalModelCatalog.filtered(query: "", purpose: "All", smallestFirst: true)
        XCTAssertEqual(result.map { $0.descriptor.byteCount }, result.map { $0.descriptor.byteCount }.sorted())
        let entry = LocalModelCatalog.entries.first { $0.id == LocalModelCatalog.defaultModel.id }!
        XCTAssertEqual(entry.requiredFreeStorageBytes, 1_082_800_064)
        XCTAssertFalse(entry.meetsRAMGuidance(physicalMemory: 3_999_999_999))
        XCTAssertTrue(entry.meetsRAMGuidance(physicalMemory: 4_000_000_000))
    }
    func testLegacyImportedManifestDecodesWithoutCatalogFields() throws {
        let data = Data("""
        [{"id":"custom","name":"Imported","fileName":"custom.gguf","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byteCount":32,"license":"User-provided"}]
        """.utf8)
        let records = try JSONDecoder().decode([LocalModelDescriptor].self, from: data)
        XCTAssertEqual(records.first?.id, "custom")
        XCTAssertNil(records.first?.downloadURL)
    }
}
