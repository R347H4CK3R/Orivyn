import XCTest
@testable import JarvisEVO

final class ModelInstallTransactionTests: XCTestCase {
    private enum Failure: Error { case injected }
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func write(_ value: String, _ name: String, _ root: URL) throws {
        try Data(value.utf8).write(to: root.appendingPathComponent(name))
    }
    private func read(_ name: String, _ root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }
    func testSuccessfulCommitPublishesBothFiles() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("old", "model.gguf", root); try write("old manifest", "installed-models.json", root)
        try write("new", "input", root)
        try ModelInstallTransaction.commit(root: root, targetName: "model.gguf", source: root.appendingPathComponent("input"), manifest: Data("new manifest".utf8))
        XCTAssertEqual(try read("model.gguf", root), "new")
        XCTAssertEqual(try read("installed-models.json", root), "new manifest")
        try ModelInstallTransaction.recover(root: root)
        XCTAssertEqual(try read("model.gguf", root), "new")
    }
    func testEachPublicationFailureRestoresBothOldFiles() throws {
        for phase in [ModelInstallTransaction.Publication.model, .manifest] {
            let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            try write("old", "model.gguf", root); try write("old manifest", "installed-models.json", root); try write("new", "input", root)
            XCTAssertThrowsError(try ModelInstallTransaction.commit(root: root, targetName: "model.gguf", source: root.appendingPathComponent("input"), manifest: Data("new manifest".utf8), didPublish: { if $0 == phase { throw Failure.injected } }))
            XCTAssertEqual(try read("model.gguf", root), "old")
            XCTAssertEqual(try read("installed-models.json", root), "old manifest")
        }
    }
    func testFailedFirstInstallLeavesNoModelOrManifest() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("new", "input", root)
        XCTAssertThrowsError(try ModelInstallTransaction.commit(root: root, targetName: "model.gguf", source: root.appendingPathComponent("input"), manifest: Data("manifest".utf8), didPublish: { _ in throw Failure.injected }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("model.gguf").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("installed-models.json").path))
    }
    func testPreparationFailureCannotChangeExistingFiles() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("old", "model.gguf", root); try write("old manifest", "installed-models.json", root); try write("new", "input", root)
        XCTAssertThrowsError(try ModelInstallTransaction.commit(root: root, targetName: "model.gguf", source: root.appendingPathComponent("input"), manifest: Data(), prepareFile: { _ in throw Failure.injected }))
        XCTAssertEqual(try read("model.gguf", root), "old")
        XCTAssertEqual(try read("installed-models.json", root), "old manifest")
    }
    func testRestartRecoversInterruptedPublicationAndIsIdempotent() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appendingPathComponent(".model-install-transaction")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        try write("old", "old-model", journal); try write("old manifest", "old-manifest", journal)
        try write(#"{"targetName":"model.gguf","hadModel":true,"hadManifest":true,"version":1}"#, "prepared.json", journal)
        try write("new", "model.gguf", root); try write("new manifest", "installed-models.json", root)
        try ModelInstallTransaction.recover(root: root)
        try ModelInstallTransaction.recover(root: root)
        XCTAssertEqual(try read("model.gguf", root), "old")
        XCTAssertEqual(try read("installed-models.json", root), "old manifest")
    }
    func testMissingRecoveryBackupFailsClosedWithoutChangingTargets() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appendingPathComponent(".model-install-transaction")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        try write("old", "old-model", journal)
        try write(#"{"targetName":"model.gguf","hadModel":true,"hadManifest":true,"version":1}"#, "prepared.json", journal)
        try write("new", "model.gguf", root)
        XCTAssertThrowsError(try ModelInstallTransaction.recover(root: root))
        XCTAssertEqual(try read("model.gguf", root), "new")
        XCTAssertEqual(try read("old-model", journal), "old")
    }
    func testPartialRollbackRetainsBackupsAndRetryRestoresBoth() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("old", "model.gguf", root); try write("old manifest", "installed-models.json", root); try write("new", "input", root)
        let directory = root.appendingPathComponent(".model-install-transaction")
        let blockedScratch = directory.appendingPathComponent("restore-manifest")
        XCTAssertThrowsError(try ModelInstallTransaction.commit(root: root, targetName: "model.gguf", source: root.appendingPathComponent("input"), manifest: Data("new manifest".utf8), didPublish: { phase in
            if phase == .manifest {
                try FileManager.default.createSymbolicLink(atPath: blockedScratch.path, withDestinationPath: root.appendingPathComponent("input").path)
                throw Failure.injected
            }
        }))
        XCTAssertEqual(try read("model.gguf", root), "old")
        XCTAssertEqual(try read("installed-models.json", root), "new manifest")
        XCTAssertEqual(try read("old-model", directory), "old")
        XCTAssertEqual(try read("old-manifest", directory), "old manifest")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("prepared.json").path))
        try FileManager.default.removeItem(at: blockedScratch)
        try ModelInstallTransaction.recover(root: root)
        XCTAssertEqual(try read("model.gguf", root), "old")
        XCTAssertEqual(try read("installed-models.json", root), "old manifest")
    }

    func testUnpreparedOrCommittedStagingCleanupNeverTouchesLiveFiles() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent(".model-install-transaction")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write("old backup", "old-model", directory)
        try write("live", "model.gguf", root); try write("live manifest", "installed-models.json", root)
        try ModelInstallTransaction.recover(root: root)
        XCTAssertEqual(try read("model.gguf", root), "live")
        XCTAssertEqual(try read("installed-models.json", root), "live manifest")
    }

    func testDeletionCommitsBytesAndManifestTogether() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("old", "model.gguf", root); try write("old manifest", "installed-models.json", root)
        try ModelInstallTransaction.remove(root: root, targetName: "model.gguf", manifest: Data("[]".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("model.gguf").path))
        XCTAssertEqual(try read("installed-models.json", root), "[]")
        try ModelInstallTransaction.recover(root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("model.gguf").path))
    }

    func testDeletionFailureAfterEitherPublicationRestoresOriginalBytes() throws {
        for phase in [ModelInstallTransaction.Publication.model, .manifest] {
            let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            try write("old", "model.gguf", root); try write("old manifest", "installed-models.json", root)
            XCTAssertThrowsError(try ModelInstallTransaction.remove(root: root, targetName: "model.gguf", manifest: Data("[]".utf8), didPublish: { if $0 == phase { throw Failure.injected } }))
            XCTAssertEqual(try read("model.gguf", root), "old")
            XCTAssertEqual(try read("installed-models.json", root), "old manifest")
        }
    }

    func testDeletingAlreadyAbsentModelStillUpdatesManifest() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("stale manifest", "installed-models.json", root)
        try ModelInstallTransaction.remove(root: root, targetName: "model.gguf", manifest: Data("[]".utf8))
        XCTAssertEqual(try read("installed-models.json", root), "[]")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("model.gguf").path))
    }

    func testAbsentModelDeletionFailurePreservesAbsenceAndOldManifest() throws {
        for phase in [ModelInstallTransaction.Publication.model, .manifest] {
            let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            try write("old manifest", "installed-models.json", root)
            XCTAssertThrowsError(try ModelInstallTransaction.remove(root: root, targetName: "model.gguf", manifest: Data("[]".utf8), didPublish: { if $0 == phase { throw Failure.injected } }))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("model.gguf").path))
            XCTAssertEqual(try read("installed-models.json", root), "old manifest")
        }
    }

    func testDeletionPreparationFailureLeavesOriginalBytesAndMetadata() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("old", "model.gguf", root); try write("old manifest", "installed-models.json", root)
        XCTAssertThrowsError(try ModelInstallTransaction.remove(root: root, targetName: "model.gguf", manifest: Data("[]".utf8), prepareFile: { _ in throw Failure.injected }))
        XCTAssertEqual(try read("model.gguf", root), "old")
        XCTAssertEqual(try read("installed-models.json", root), "old manifest")
    }

    func testRestartAfterInterruptedDeletionRestoresModelAndManifest() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appendingPathComponent(".model-install-transaction")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        try write("old", "old-model", journal); try write("old manifest", "old-manifest", journal)
        try write(#"{"targetName":"model.gguf","hadModel":true,"hadManifest":true,"version":1}"#, "prepared.json", journal)
        try write("[]", "installed-models.json", root)
        try ModelInstallTransaction.recover(root: root)
        XCTAssertEqual(try read("model.gguf", root), "old")
        XCTAssertEqual(try read("installed-models.json", root), "old manifest")
    }

    func testDeletionRetainsOriginalInodeWithoutCopyingLargeModelWhenLinksSupported() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("model bytes", "model.gguf", root); try write("manifest", "installed-models.json", root)
        let original = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("model.gguf").path)[.systemFileNumber] as? NSNumber
        XCTAssertNotNil(original)
        try ModelInstallTransaction.remove(root: root, targetName: "model.gguf", manifest: Data("[]".utf8), didPublish: { phase in
            if phase == .model {
                let backup = root.appendingPathComponent(".model-install-transaction/old-model")
                let retained = try FileManager.default.attributesOfItem(atPath: backup.path)[.systemFileNumber] as? NSNumber
                XCTAssertEqual(retained, original)
                XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "model bytes")
            }
        })
    }

    func testTraversalAndSymlinkTargetsAreRejected() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("input", "input", root)
        for name in ["../escape.gguf", "installed-models.json", ".model-install-transaction", "bad\0.gguf"] {
            XCTAssertThrowsError(try ModelInstallTransaction.commit(root: root, targetName: name, source: root.appendingPathComponent("input"), manifest: Data()))
        }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("linked.gguf").path, withDestinationPath: root.appendingPathComponent("input").path)
        XCTAssertThrowsError(try ModelInstallTransaction.commit(root: root, targetName: "linked.gguf", source: root.appendingPathComponent("input"), manifest: Data()))
        XCTAssertEqual(try read("input", root), "input")
    }
}
