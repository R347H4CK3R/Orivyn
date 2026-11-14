import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import JarvisEVO

final class AttachmentFileCopyTests: XCTestCase {
    func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    func testOversizedSourceCannotWriteBeyondLimitOrLeaveDestination() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source")
            let destination = root.appendingPathComponent("destination")
            try Data(repeating: 42, count: 100_000).write(to: source)
            XCTAssertThrowsError(try AttachmentFileCopy.copy(from: source, to: destination, maximumBytes: 65_536))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }
    func testExactLimitCopiesIdenticalBytes() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source")
            let destination = root.appendingPathComponent("destination")
            let data = Data((0..<131_072).map { UInt8($0 % 251) })
            try data.write(to: source)
            XCTAssertEqual(try AttachmentFileCopy.copy(from: source, to: destination, maximumBytes: data.count), data.count)
            XCTAssertEqual(try Data(contentsOf: destination), data)
            XCTAssertEqual(try Data(contentsOf: source), data)
        }
    }

    func testEmptySourceLeavesNoDestination() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
            try Data().write(to: source)
            XCTAssertThrowsError(try AttachmentFileCopy.copy(from: source, to: destination, maximumBytes: 10))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testExistingDestinationIsPreserved() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
            try Data("new".utf8).write(to: source)
            try Data("original".utf8).write(to: destination)
            XCTAssertThrowsError(try AttachmentFileCopy.copy(from: source, to: destination, maximumBytes: 10))
            XCTAssertEqual(try Data(contentsOf: destination), Data("original".utf8))
        }
    }

    func testSourceSymlinkIsRejectedWithoutFollowingTarget() throws {
        try withDirectory { root in
            let target = root.appendingPathComponent("target"), source = root.appendingPathComponent("source")
            let destination = root.appendingPathComponent("destination")
            try Data("private".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: target)
            XCTAssertThrowsError(try AttachmentFileCopy.copy(from: source, to: destination, maximumBytes: 10))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(try Data(contentsOf: target), Data("private".utf8))
        }
    }

    func testDestinationSymlinkIsPreservedWithoutFollowingTarget() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
            let destination = root.appendingPathComponent("destination")
            try Data("new".utf8).write(to: source)
            try Data("original".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
            XCTAssertThrowsError(try AttachmentFileCopy.copy(from: source, to: destination, maximumBytes: 10))
            XCTAssertEqual(try Data(contentsOf: target), Data("original".utf8))
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), target.path)
        }
    }

    func testFIFOIsRejectedWithoutBlocking() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("fifo"), destination = root.appendingPathComponent("destination")
            XCTAssertEqual(mkfifo(source.path, 0o600), 0)
            XCTAssertThrowsError(try AttachmentFileCopy.copy(from: source, to: destination, maximumBytes: 10))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testDirectorySourceIsRejected() throws {
        try withDirectory { root in
            let destination = root.appendingPathComponent("destination")
            XCTAssertThrowsError(try AttachmentFileCopy.copy(from: root, to: destination, maximumBytes: 10))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testMissingSourceDoesNotCreateDestination() throws {
        try withDirectory { root in
            let destination = root.appendingPathComponent("destination")
            XCTAssertThrowsError(try AttachmentFileCopy.copy(from: root.appendingPathComponent("missing"), to: destination, maximumBytes: 10))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testInvalidLimitsDoNotTouchFiles() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
            try Data("abc".utf8).write(to: source)
            for limit in [0, -1, Int.min] {
                XCTAssertThrowsError(try AttachmentFileCopy.copy(from: source, to: destination, maximumBytes: limit))
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            }
        }
    }

    func testMaximumIntegerLimitDoesNotOverflow() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
            try Data("abc".utf8).write(to: source)
            XCTAssertEqual(try AttachmentFileCopy.copy(from: source, to: destination, maximumBytes: Int.max), 3)
        }
    }

    func testNonFileURLIsRejected() throws {
        try withDirectory { root in
            let destination = root.appendingPathComponent("destination")
            XCTAssertThrowsError(try AttachmentFileCopy.copy(from: URL(string: "https://example.com/file")!, to: destination, maximumBytes: 10))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testPrecancelledCopyLeavesSourceAndDestinationUntouched() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
        try Data("abc".utf8).write(to: source)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try AttachmentFileCopy.copy(from: source, to: destination, maximumBytes: 10)
        }
        do { _ = try await task.value; XCTFail("Cancelled import must not copy") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: source), Data("abc".utf8))
    }

}
