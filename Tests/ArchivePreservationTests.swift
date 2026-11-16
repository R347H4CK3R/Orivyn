import XCTest
#if canImport(Preservation)
@testable import Preservation
#else
@testable import JarvisEVO
#endif

final class ArchivePreservationTests: XCTestCase {
    func testCopiesAndRevalidatesWithoutChangingOriginal() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.zip")
        let bytes = Data(repeating: 37, count: 150_000)
        try bytes.write(to: source)
        let staging = root.appendingPathComponent("job")
        let manifest = try ArchivePreservation.preserve(source: source, staging: staging)
        XCTAssertEqual(manifest.bytes, 150_000)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: staging.appendingPathComponent("original.zip")), bytes)
        XCTAssertEqual(try ArchivePreservation.revalidate(staging: staging), manifest)
    }

    func fixture(_ body: (URL, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.zip")
        try Data(repeating: 42, count: 150_000).write(to: source)
        try body(root, source, root.appendingPathComponent("job"))
    }
    func testExistingStagingIsNeverOverwritten() throws {
        try fixture { _, source, staging in
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let file = staging.appendingPathComponent("original.zip")
            try Data("keep".utf8).write(to: file)
            XCTAssertThrowsError(try ArchivePreservation.preserve(source: source, staging: staging))
            XCTAssertEqual(try Data(contentsOf: file), Data("keep".utf8))
        }
    }
    func testRejectsSourceSymlinkBeforeCreatingStaging() throws {
        try fixture { root, source, staging in
            let link = root.appendingPathComponent("linked.zip")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
            XCTAssertThrowsError(try ArchivePreservation.preserve(source: link, staging: staging))
            XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        }
    }
    func testRevalidationRejectsCorruptionAndSymlinkReplacement() throws {
        try fixture { root, source, staging in
            let manifest = try ArchivePreservation.preserve(source: source, staging: staging)
            let file = staging.appendingPathComponent("original.zip")
            try Data(repeating: 43, count: 150_000).write(to: file)
            XCTAssertThrowsError(try ArchivePreservation.revalidate(staging: staging))
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: source)
            XCTAssertThrowsError(try ArchivePreservation.revalidate(staging: staging))
            XCTAssertEqual(manifest.bytes, 150_000)
        }
    }
    func testCancellationRetainsPartialWithoutCompleteManifest() throws {
        try fixture { _, source, staging in
            XCTAssertThrowsError(try ArchivePreservation.preserve(source: source, staging: staging, progress: { phase, bytes in
                if phase == "copy" && bytes >= 65_536 { throw CancellationError() }
            }))
            XCTAssertTrue(FileManager.default.fileExists(atPath: staging.appendingPathComponent("original.zip").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: staging.appendingPathComponent("verified-manifest.json").path))
            XCTAssertThrowsError(try ArchivePreservation.revalidate(staging: staging))
            XCTAssertEqual(try Data(contentsOf: source).count, 150_000)
        }
    }
    func testSourceLimitRejectsBeforeStaging() throws {
        try fixture { _, source, staging in
            XCTAssertThrowsError(try ArchivePreservation.preserve(source: source, staging: staging, maximumBytes: 20))
            XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        }
    }

    func testSHA256MatchesKnownIndependentVector() throws {
        try fixture { _, source, staging in
            try Data("abc".utf8).write(to: source)
            let manifest = try ArchivePreservation.preserve(source: source, staging: staging)
            XCTAssertEqual(manifest.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            XCTAssertEqual(manifest.bytes, 3)
            let wrong = ArchivePreservation.Manifest(version: 1, bytes: 4, sha256: manifest.sha256)
            XCTAssertThrowsError(try ArchivePreservation.revalidate(staging: staging, expected: wrong))
        }
    }
    func testSourceMutationDuringCopyNeverPublishesVerifiedManifest() throws {
        try fixture { _, source, staging in
            var changed = false
            XCTAssertThrowsError(try ArchivePreservation.preserve(source: source, staging: staging, progress: { phase, _ in
                if phase == "copy" && !changed {
                    changed = true
                    try Data(repeating: 43, count: 150_000).write(to: source)
                }
            }))
            XCTAssertFalse(FileManager.default.fileExists(atPath: staging.appendingPathComponent("verified-manifest.json").path))
        }
    }
    func testInsufficientDiskCapacityFailsBeforeCopyUsingSparseSyntheticFile() throws {
        try fixture { _, source, staging in
            let handle = try FileHandle(forWritingTo: source)
            // Sparse only: no terabyte allocation/read is performed.
            try handle.truncate(atOffset: 1_099_511_627_776)
            try handle.close()
            XCTAssertThrowsError(try ArchivePreservation.preserve(source: source, staging: staging, maximumBytes: 1_099_511_627_776)) { error in
                guard case ArchivePreservation.Failure.insufficientSpace = error else { return XCTFail("Expected disk-space preflight failure, got \(error)") }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        }
    }
}
