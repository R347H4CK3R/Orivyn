import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import JarvisEVO

final class NativeModelSnapshotTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func stale(_ root: URL) throws -> URL {
        let dir = root.appendingPathComponent("OrivynNativeModel-v1-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try Data("OrivynNativeSnapshot/v1\n".utf8).write(to: dir.appendingPathComponent("owner.lock"))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent("owner.lock").path)
        try Data("synthetic model".utf8).write(to: dir.appendingPathComponent("model.gguf"))
        return dir
    }
    func testInactiveOwnedSnapshotIsRemovedButSourceAndLegacyRemain() throws {
        let root = try makeRoot(), old = try stale(root)
        let source = root.appendingPathComponent("downloaded.gguf")
        try Data("source".utf8).write(to: source)
        let legacy = root.appendingPathComponent("OrivynNativeModel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: false)
        XCTAssertEqual(try NativeModelSnapshot.cleanup(in: root), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }
    func testActiveLeasesSurviveCleanupAndReleaseRemovesOnlyOwnCopy() throws {
        let root = try makeRoot()
        var first: NativeModelSnapshot? = try NativeModelSnapshot.create(in: root)
        let second = try NativeModelSnapshot.create(in: root)
        let firstURL = try XCTUnwrap(first).directory
        try Data("one".utf8).write(to: try XCTUnwrap(first).modelURL)
        try Data("two".utf8).write(to: second.modelURL)
        XCTAssertEqual(try NativeModelSnapshot.cleanup(in: root), 0)
        first = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertEqual(try Data(contentsOf: second.modelURL), Data("two".utf8))
    }
    func testUnknownContentsAndInvalidMarkerArePreserved() throws {
        let root = try makeRoot(), extra = try stale(root), malformed = try stale(root)
        try Data("user data".utf8).write(to: extra.appendingPathComponent("keep.txt"))
        try Data("not owned".utf8).write(to: malformed.appendingPathComponent("owner.lock"))
        XCTAssertEqual(try NativeModelSnapshot.cleanup(in: root), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: extra.appendingPathComponent("model.gguf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: malformed.appendingPathComponent("model.gguf").path))
    }
    func testSymlinkDirectoryAndModelAreNeverFollowed() throws {
        let root = try makeRoot(), foreign = try makeRoot(), old = try stale(root)
        let source = foreign.appendingPathComponent("source")
        try Data("keep".utf8).write(to: source)
        try FileManager.default.removeItem(at: old.appendingPathComponent("model.gguf"))
        try FileManager.default.createSymbolicLink(at: old.appendingPathComponent("model.gguf"), withDestinationURL: source)
        let link = root.appendingPathComponent("OrivynNativeModel-v1-" + UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: foreign)
        XCTAssertEqual(try NativeModelSnapshot.cleanup(in: root), 0)
        XCTAssertEqual(try Data(contentsOf: source), Data("keep".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("owner.lock").path))
    }
    func testHardLinkedModelAndLockSymlinkRemainUntouched() throws {
        let root = try makeRoot(), linked = try stale(root), lockLink = try stale(root)
        let source = root.appendingPathComponent("source.gguf")
        try FileManager.default.linkItem(at: linked.appendingPathComponent("model.gguf"), to: source)
        try FileManager.default.removeItem(at: lockLink.appendingPathComponent("owner.lock"))
        try FileManager.default.createSymbolicLink(at: lockLink.appendingPathComponent("owner.lock"), withDestinationURL: linked.appendingPathComponent("owner.lock"))
        XCTAssertEqual(try NativeModelSnapshot.cleanup(in: root), 0)
        XCTAssertEqual(try Data(contentsOf: source), Data("synthetic model".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: linked.appendingPathComponent("model.gguf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockLink.appendingPathComponent("model.gguf").path))
    }
    func testIncompleteOwnedCopyIsRecoverableAndUnownedEmptyDirectoryStays() throws {
        let root = try makeRoot(), incomplete = try stale(root)
        try FileManager.default.removeItem(at: incomplete.appendingPathComponent("model.gguf"))
        let unknown = root.appendingPathComponent("OrivynNativeModel-v1-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: false)
        XCTAssertEqual(try NativeModelSnapshot.cleanup(in: root), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
    }
    func testRootSymlinkAndCoordinationLockSymlinkFailClosed() throws {
        let root = try makeRoot(), foreign = try makeRoot()
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: foreign)
        XCTAssertThrowsError(try NativeModelSnapshot.create(in: link))
        let target = foreign.appendingPathComponent("keep")
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".orivyn-native-snapshot-v1.lock"), withDestinationURL: target)
        XCTAssertThrowsError(try NativeModelSnapshot.cleanup(in: root))
        XCTAssertEqual(try Data(contentsOf: target), Data("keep".utf8))
    }

    func testBoundedPassRotatesPastMalformedEntries() throws {
        let root = try makeRoot()
        for index in 0..<128 {
            let name = String(format: "OrivynNativeModel-v1-00000000-0000-0000-0000-%012X", index)
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        let old = try stale(root)
        let last = root.appendingPathComponent("OrivynNativeModel-v1-FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")
        try FileManager.default.moveItem(at: old, to: last)
        XCTAssertEqual(try NativeModelSnapshot.cleanup(in: root), 0)
        XCTAssertEqual(try NativeModelSnapshot.cleanup(in: root), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: last.path))
    }
    func testFIFOCoordinationAndLeaseAreRejectedWithoutDeletingAnything() throws {
        let root = try makeRoot(), old = try stale(root)
        let marker = old.appendingPathComponent("owner.lock")
        try FileManager.default.removeItem(at: marker)
        XCTAssertEqual(mkfifo(marker.path, 0o600), 0)
        XCTAssertEqual(try NativeModelSnapshot.cleanup(in: root), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("model.gguf").path))
        try FileManager.default.removeItem(at: root.appendingPathComponent(".orivyn-native-snapshot-v1.lock"))
        XCTAssertEqual(mkfifo(root.appendingPathComponent(".orivyn-native-snapshot-v1.lock").path, 0o600), 0)
        XCTAssertThrowsError(try NativeModelSnapshot.cleanup(in: root))
    }

    func testMalformedAndOversizedCursorPreserveCursorAndSnapshots() throws {
        for bytes in [Data("unowned cursor contents".utf8), Data(repeating: 65, count: 200)] {
            let root = try makeRoot(), old = try stale(root)
            let cursor = root.appendingPathComponent(".orivyn-native-snapshot-v1.lock")
            try bytes.write(to: cursor)
            XCTAssertEqual(try NativeModelSnapshot.cleanup(in: root), 0)
            XCTAssertEqual(try Data(contentsOf: cursor), bytes)
            XCTAssertEqual(try Data(contentsOf: old.appendingPathComponent("model.gguf")), Data("synthetic model".utf8))
        }
    }

}
