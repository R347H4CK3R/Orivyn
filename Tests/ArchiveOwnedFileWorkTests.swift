import XCTest
@testable import JarvisEVO

final class ArchiveOwnedFileWorkTests: XCTestCase {
    private final class Gate: @unchecked Sendable {
        let created = DispatchSemaphore(value: 0)
        let finish = DispatchSemaphore(value: 0)
    }
    func testLateSuccessfulProducerTransfersOwnershipBeforeCancellationCheck() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("owned.txt"), gate = Gate()
        let task = Task {
            let owned = try await ArchiveOwnedFileWork.run {
                try Data("private temporary copy".utf8).write(to: file)
                gate.created.signal()
                guard gate.finish.wait(timeout: .now() + 10) == .success else { throw CocoaError(.fileReadUnknown) }
                return file // Deliberately emulate a late non-cancellable success.
            }
            defer { try? FileManager.default.removeItem(at: owned) }
            try Task.checkCancellation()
        }
        XCTAssertEqual(gate.created.wait(timeout: .now() + 10), .success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        task.cancel(); gate.finish.signal()
        do { try await task.value; XCTFail("Cancellation must remain visible to caller") }
        catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "Successful output must not be lost before caller cleanup is installed")
    }
    func testNormalSuccessTransfersFileWithoutDeletingIt() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let owned = try await ArchiveOwnedFileWork.run { try Data("kept".utf8).write(to: file); return file }
        XCTAssertEqual(owned, file)
        XCTAssertEqual(try Data(contentsOf: owned), Data("kept".utf8))
    }
}
