import XCTest
@testable import JarvisEVO

final class LocalModelStoreTests: XCTestCase {
    private func fixture() throws -> (URL, LocalModelStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (root, try LocalModelStore(root: root))
    }

    func testImportRejectsNonGGUFWithoutInstallingIt() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("invalid.gguf")
        try Data("not a model".utf8).write(to: input)
        do {
            _ = try await store.importModel(from: input)
            XCTFail("Invalid bytes must not be installed")
        } catch LocalModelError.invalidGGUF { }
        let models = try await store.installedModels()
        XCTAssertTrue(models.isEmpty)
    }

    func testImportRecordsDigestAndDetectsPostInstallTampering() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("fixture.gguf")
        // A minimal GGUF v3 header tests storage validation, not model inference.
        let bytes = Data([0x47,0x47,0x55,0x46,3,0,0,0] + Array(repeating: 0, count: 24))
        try bytes.write(to: input)
        let descriptor = try await store.importModel(from: input)
        let installed = try await store.verifiedURL(for: descriptor)
        XCTAssertEqual(try Data(contentsOf: installed), bytes)
        var changed = bytes
        changed[31] = 1
        try changed.write(to: installed)
        do {
            _ = try await store.verifiedURL(for: descriptor)
            XCTFail("Modified model must not pass verification")
        } catch LocalModelError.integrityMismatch { }
    }

    func testMissingModelNeverReturnsUsableURL() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await store.verifiedURL(for: LocalModelCatalog.defaultModel)
            XCTFail("Absent model must not be reported as ready")
        } catch LocalModelError.notInstalled { }
    }

    func testDescriptorCannotEscapeModelDirectory() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = LocalModelDescriptor(id: "escape", name: "Escape", fileName: "../escape.gguf", downloadURL: nil, sha256: String(repeating: "a", count: 64), byteCount: 32, license: "Unknown", sourceURL: nil)
        do {
            _ = try await store.verifiedURL(for: descriptor)
            XCTFail("Path traversal must be rejected")
        } catch LocalModelError.invalidDescriptor { }
    }

    func testRemovingInstalledModelAlsoRemovesManifestEntry() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("fixture.gguf")
        try Data([0x47,0x47,0x55,0x46,3,0,0,0] + Array(repeating: 0, count: 24)).write(to: input)
        let descriptor = try await store.importModel(from: input)
        try await store.remove(descriptor)
        let installed = await store.isInstalled(descriptor)
        let models = try await store.installedModels()
        XCTAssertFalse(installed)
        XCTAssertTrue(models.isEmpty)
    }
}
