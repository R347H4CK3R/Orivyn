import XCTest
@testable import JarvisEVO

final class ArchiveReadBufferTests: XCTestCase {
    func testChunkContentsAndEOFArePreserved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = Data((0..<150_000).map { UInt8($0 % 251) })
        try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var joined = Data()
        while let block = try ArchiveReadBuffer.read(handle, upToCount: 65_536), !block.isEmpty { joined.append(block) }
        XCTAssertEqual(joined, data)
        XCTAssertTrue(try ArchiveReadBuffer.read(handle, upToCount: 65_536)?.isEmpty ?? true)
    }
    func testInvalidCountIsRejectedBeforeReading() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([42]).write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        for count in [0, -1, 65_537] { XCTAssertThrowsError(try ArchiveReadBuffer.read(handle, upToCount: count)) }
        XCTAssertEqual(try ArchiveReadBuffer.read(handle, upToCount: 1), Data([42]))
    }
    func testClosedHandleErrorIsNotSuppressed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([42]).write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url); try handle.close()
        XCTAssertThrowsError(try ArchiveReadBuffer.read(handle, upToCount: 1))
    }
}
