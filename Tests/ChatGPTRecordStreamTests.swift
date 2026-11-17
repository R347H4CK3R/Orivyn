import XCTest
@testable import JarvisEVO

final class ChatGPTRecordStreamTests: XCTestCase {
    func testStreamFailuresExplainRecovery() {
        XCTAssertTrue(ChatGPTRecordStream.Failure.limit.localizedDescription.contains("smaller export"))
        XCTAssertTrue(ChatGPTRecordStream.Failure.format.localizedDescription.contains("valid JSON"))
    }

    func withFile<T>(_ text: String, body: (FileHandle) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        return try body(handle)
    }
    func testRejectsDuplicateDecodedObjectKeysBeforeConsumer() throws {
        for source in [#"[{"is_do_not_remember":true,"is_do_not_remember":false}]"#,
                       #"[{"is_do_not_remember":true,"is_do_not_reme\u006dber":false}]"#] {
            var consumed = false
            try withFile(source) { handle in
                XCTAssertThrowsError(try ChatGPTRecordStream.read(handle) { _ in consumed = true })
            }
            XCTAssertFalse(consumed)
        }
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

    func testUnknownSubtreesStillValidateEveryJSONToken() throws {
        let bad = [#"{"x":01}"#, #"{"x":1.}"#, #"{"x":1e}"#, #"{"x":1e9999}"#,
                   #"{"x":[1,]}"#, #"{"x":{"a":1,}}"#, #"{"x":tru}"#,
                   #"{"x":"\q"}"#, #"{"x":"\uD800"}"#, #"{"x":"\uDC00"}"#,
                   #"{"x":"\uD800\u0041"}"#, #"{"x":NaN}"#]
        for value in bad { try withFile("[" + value + "]") { handle in
            XCTAssertThrowsError(try ChatGPTRecordStream.read(handle) { _ in XCTFail("Invalid unknown value accepted: \(value)") })
        } }
        for value in [#"{"x":"\uD834\uDD1E"}"#, #"{"x":[-0,1e-9,true,false,null]}"#,
                      #"{"unknown":{"x":1,"x":2}}"#] {
            try withFile("[" + value + "]") { XCTAssertNoThrow(try ChatGPTRecordStream.read($0) { _ in }) }
        }
        XCTAssertThrowsError(try ChatGPTRecordProjection.validate(Data([123,34,120,34,58,34,255,34,125])))
    }
}
