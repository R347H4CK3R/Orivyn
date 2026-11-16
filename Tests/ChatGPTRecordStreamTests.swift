import XCTest
@testable import JarvisEVO

final class ChatGPTRecordStreamTests: XCTestCase {
    func withFile<T>(_ text: String, body: (FileHandle) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        return try body(handle)
    }
    func testStreamsObjectsWithoutSplittingEscapedStringsOrNestedArrays() throws {
        let source = #"[{"text":"quoted \" } [ ","parts":[{"n":1}]},{"n":2}]"#
        var records: [Data] = []
        let result = try withFile(source) { try ChatGPTRecordStream.read($0) { records.append($0) } }
        XCTAssertEqual(result.records, 2)
        XCTAssertEqual(result.bytes, source.utf8.count)
        guard records.count == 2 else { return XCTFail("Expected two streamed records") }
        XCTAssertEqual((try JSONSerialization.jsonObject(with: records[1]) as? [String: Int])?["n"], 2)
    }
    func testRejectsTruncatedTrailingAndNonObjectRecords() throws {
        for source in ["[{", "[{},]", "[]garbage", "[1]", "[{}", "[{]}", "[{invalid}]"] {
            try withFile(source) { handle in XCTAssertThrowsError(try ChatGPTRecordStream.read(handle) { _ in }) }
        }
    }
    func testBudgetsRejectBeforeAcceptingTooManyOrOversizedRecords() throws {
        try withFile("[{},{}]") { handle in
            XCTAssertThrowsError(try ChatGPTRecordStream.read(handle, limits: .init(recordBytes: 20, totalBytes: 100, records: 1, nesting: 3)) { _ in })
        }
        try withFile(#"[{"abcdef":123}]"#) { handle in
            XCTAssertThrowsError(try ChatGPTRecordStream.read(handle, limits: .init(recordBytes: 4, totalBytes: 100, records: 1, nesting: 3)) { _ in })
        }
        try withFile(#"[{"x":[[[]]]}]"#) { handle in
            XCTAssertThrowsError(try ChatGPTRecordStream.read(handle, limits: .init(recordBytes: 100, totalBytes: 100, records: 1, nesting: 2)) { _ in })
        }
    }
    func testConsumerFailureStopsBeforeNextRecord() throws {
        enum Stop: Error { case now }
        var count = 0
        try withFile("[{},{}]") { handle in
            XCTAssertThrowsError(try ChatGPTRecordStream.read(handle) { _ in count += 1; throw Stop.now })
        }
        XCTAssertEqual(count, 1)
    }

    func testRecordsCrossReadChunkBoundariesAndEmptyArrays() throws {
        let payload = String(repeating: "é\"\\", count: 30_000)
        let source = String(data: try JSONSerialization.data(withJSONObject: [["text": payload], ["text": "second"]]), encoding: .utf8)!
        var seen: [String] = []
        let report = try withFile(source) { try ChatGPTRecordStream.read($0) { data in
            let record = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
            seen.append(try XCTUnwrap(record["text"]))
        } }
        XCTAssertEqual(report.records, 2); XCTAssertEqual(seen, [payload, "second"])
        XCTAssertEqual(try withFile(" [] ") { try ChatGPTRecordStream.read($0) { _ in XCTFail("Empty array") } }.records, 0)
    }
}
