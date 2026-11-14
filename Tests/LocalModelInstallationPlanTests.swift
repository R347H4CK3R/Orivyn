import XCTest
@testable import JarvisEVO

final class LocalModelInstallationPlanTests: XCTestCase {
    private func model(_ id: String, file: String, hash: String = "a") -> LocalModelDescriptor {
        LocalModelDescriptor(id: id, name: id, fileName: file, downloadURL: nil,
            sha256: String(repeating: hash, count: 64), byteCount: 32, license: "fixture", sourceURL: nil)
    }
    func testNewModelPreservesExistingEntries() throws {
        let a = model("a", file: "a.gguf"), b = model("b", file: "b.gguf")
        XCTAssertEqual(try LocalModelInstallationPlan.updatedManifest(installing: b, from: [a]), [a,b])
    }
    func testReplacingSameOwnerPreservesOtherEntries() throws {
        let a = model("a", file: "a.gguf"), b = model("b", file: "b.gguf")
        let replacement = model("a", file: "a.gguf", hash: "b")
        XCTAssertEqual(try LocalModelInstallationPlan.updatedManifest(installing: replacement, from: [a,b]), [b,replacement])
    }
    func testDifferentIDCannotTakeOwnershipOfExistingModelFile() throws {
        let existing = model("installed", file: "shared.gguf")
        let incoming = model("new-id", file: "shared.gguf", hash: "b")
        XCTAssertThrowsError(try LocalModelInstallationPlan.updatedManifest(installing: incoming, from: [existing])) {
            XCTAssertEqual($0 as? LocalModelInstallationPlanError, .fileOwnedByAnotherModel)
        }
    }
    func testRejectedOwnershipCollisionPreservesPublishedBytesAndManifest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = model("installed", file: "shared.gguf")
        let incoming = model("new-id", file: "shared.gguf", hash: "b")
        let target = root.appendingPathComponent(existing.fileName)
        let manifestURL = root.appendingPathComponent("installed-models.json")
        let original = Data("original model bytes".utf8)
        let originalManifest = try JSONEncoder().encode([existing])
        try original.write(to: target)
        try originalManifest.write(to: manifestURL)
        let source = root.appendingPathComponent("incoming")
        try Data("replacement model bytes".utf8).write(to: source)
        XCTAssertThrowsError(try {
            let manifest = try LocalModelInstallationPlan.updatedManifest(installing: incoming, from: [existing])
            try ModelInstallTransaction.commit(root: root, targetName: incoming.fileName,
                source: source, manifest: JSONEncoder().encode(manifest))
        }()) {
            XCTAssertEqual($0 as? LocalModelInstallationPlanError, .fileOwnedByAnotherModel)
        }
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try Data(contentsOf: manifestURL), originalManifest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".model-install-transaction").path))
    }
    func testCaseOnlyAliasCannotTakeAnotherModelsFile() {
        let existing = model("installed", file: "Model.gguf")
        let incoming = model("new-id", file: "model.gguf")
        XCTAssertThrowsError(try LocalModelInstallationPlan.updatedManifest(installing: incoming, from: [existing])) {
            XCTAssertEqual($0 as? LocalModelInstallationPlanError, .fileOwnedByAnotherModel)
        }
    }
    func testSameIDFilenameChangeRetainsManifestReplacementSemantics() throws {
        let existing = model("installed", file: "old.gguf")
        let incoming = model("installed", file: "new.gguf")
        XCTAssertEqual(try LocalModelInstallationPlan.updatedManifest(installing: incoming, from: [existing]), [incoming])
    }
    func testCanonicalUnicodeAliasCannotTakeAnotherModelsFile() {
        let existing = model("installed", file: "Caf\u{00e9}.gguf")
        let incoming = model("new-id", file: "cafe\u{0301}.gguf")
        XCTAssertThrowsError(try LocalModelInstallationPlan.updatedManifest(installing: incoming, from: [existing])) {
            XCTAssertEqual($0 as? LocalModelInstallationPlanError, .fileOwnedByAnotherModel)
        }
    }
}
