import XCTest
@testable import JarvisEVO

@MainActor
final class BackupFileReaderTests: XCTestCase {
    private func file(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testBoundedReaderAcceptsExactLimitAndRejectsAdditionalByte() throws {
        let exact = try file(Data(repeating: 65, count: 16))
        XCTAssertEqual(try BackupFileReader.readBounded(exact, maximumBytes: 16).count, 16)
        let oversized = try file(Data(repeating: 65, count: 17))
        XCTAssertThrowsError(try BackupFileReader.readBounded(oversized, maximumBytes: 16))
    }
    func testSymbolicLinkIsRejected() throws {
        let original = try file(Data("backup".utf8))
        let link = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        defer { try? FileManager.default.removeItem(at: link) }
        XCTAssertThrowsError(try BackupFileReader.readBounded(link))
    }
    func testEmptyAndDirectoryAreRejected() throws {
        let empty = try file(Data())
        XCTAssertThrowsError(try BackupFileReader.readBounded(empty))
        XCTAssertThrowsError(try BackupFileReader.readBounded(FileManager.default.temporaryDirectory))
    }
    func testCoordinatedReadRetainsExactBytesAndCancelledTaskDoesNotRead() async throws {
        let data = Data("{\"schemaVersion\":1}".utf8)
        let url = try file(data)
        let loaded = try await BackupFileReader.read(url)
        XCTAssertEqual(loaded, data)
        let task = Task { try await BackupFileReader.read(url) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled read succeeded") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
