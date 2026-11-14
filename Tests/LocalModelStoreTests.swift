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

    func testReopeningStoreRecoversInterruptedInstallBeforeInferenceLookup() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("fixture.gguf")
        let original = Data([0x47,0x47,0x55,0x46,3,0,0,0] + Array(repeating: 0, count: 24))
        try original.write(to: input)
        let descriptor = try await store.importModel(from: input)
        let installed = try await store.verifiedURL(for: descriptor)
        let journal = root.appendingPathComponent(".model-install-transaction")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: installed, to: journal.appendingPathComponent("old-model"))
        try FileManager.default.copyItem(at: root.appendingPathComponent("installed-models.json"), to: journal.appendingPathComponent("old-manifest"))
        let marker: [String: Any] = ["targetName": descriptor.fileName, "hadModel": true, "hadManifest": true, "version": 1]
        try JSONSerialization.data(withJSONObject: marker).write(to: journal.appendingPathComponent("prepared.json"))
        try Data("interrupted replacement".utf8).write(to: installed)
        try Data("[]".utf8).write(to: root.appendingPathComponent("installed-models.json"))
        let reopened = try LocalModelStore(root: root)
        let recovered = try await reopened.verifiedURL(for: descriptor)
        XCTAssertEqual(try Data(contentsOf: recovered), original)
        let models = try await reopened.installedModels()
        XCTAssertEqual(models.map(\.id), [descriptor.id])
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
    func testStaleOrUnknownRemovalPreservesCurrentModelAndMetadata() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("fixture.gguf")
        let bytes = Data([0x47,0x47,0x55,0x46,3,0,0,0] + Array(repeating: 0, count: 24))
        try bytes.write(to: input)
        let current = try await store.importModel(from: input)
        let installed = try await store.verifiedURL(for: current)
        let manifest = root.appendingPathComponent("installed-models.json")
        let originalMetadata = try Data(contentsOf: manifest)
        for id in [current.id, "unknown-selection"] {
            let stale = LocalModelDescriptor(id: id, name: "Old selection", fileName: current.fileName,
                downloadURL: current.downloadURL, sha256: current.sha256, byteCount: current.byteCount,
                license: current.license, sourceURL: current.sourceURL)
            do { try await store.remove(stale); XCTFail("Stale or unknown selection must not remove current bytes") }
            catch LocalModelRemovalPlanError.staleDescriptor { }
            XCTAssertEqual(try Data(contentsOf: installed), bytes)
            XCTAssertEqual(try Data(contentsOf: manifest), originalMetadata)
        }
    }

}
