import XCTest
@testable import JarvisEVO

final class LocalToolResultBudgetTests: XCTestCase {
    func testSmallResultBytesRemainUnchanged() throws {
        let object: MCPJSONValue = .object(["models": .array([.string("small")]), "totalInstalled": .integer(1)])
        XCTAssertEqual(try LocalToolResultBudget.encode(object, collection: "models", maximumBytes: 4096), try object.encoded())
    }
    func testOversizedEscapedResultsKeepWholePrefixAndExplicitOmissionCount() throws {
        let items: [MCPJSONValue] = (0..<10).map { .object(["id": .integer(Int64($0)), "title": .string(String(repeating: "\n", count: 96)), "excerpt": .string(String(repeating: "\t", count: 160))]) }
        let object: MCPJSONValue = .object(["matches": .array(items), "searchedConversations": .integer(10), "searchLimited": .bool(false)])
        XCTAssertGreaterThan(try object.encoded(maximumBytes: 20_480).count, 4096)
        let data = try LocalToolResultBudget.encode(object, collection: "matches", maximumBytes: 4096)
        XCTAssertLessThanOrEqual(data.count, 4096)
        let decoded = try MCPJSONValue.parse(data).objectValue!
        let retained = decoded["matches"]!.arrayValue!
        XCTAssertFalse(retained.isEmpty); XCTAssertLessThan(retained.count, 10)
        XCTAssertEqual(retained, Array(items.prefix(retained.count)))
        XCTAssertEqual(decoded["resultTruncated"], .bool(true))
        XCTAssertEqual(decoded["omittedItems"], .integer(Int64(10-retained.count)))
        XCTAssertEqual(decoded["searchedConversations"], .integer(10))
        XCTAssertEqual(object.objectValue?["matches"]?.arrayValue?.count, 10)
    }
    func testUnfitSingleItemBecomesExplicitEmptyResultNotInvalidJSON() throws {
        let object: MCPJSONValue = .object(["models": .array([.string(String(repeating: "x", count: 8000))])])
        let decoded = try MCPJSONValue.parse(LocalToolResultBudget.encode(object, collection: "models", maximumBytes: 4096)).objectValue!
        XCTAssertEqual(decoded["models"], .array([]))
        XCTAssertEqual(decoded["omittedItems"], .integer(1))
    }
    func testInvalidBudgetOrUnboundedMetadataFailsClosed() throws {
        let object: MCPJSONValue = .object(["models": .array([])])
        for size in [-1, 0, 16, 20_481] { XCTAssertThrowsError(try LocalToolResultBudget.encode(object, collection: "models", maximumBytes: size)) }
        XCTAssertThrowsError(try LocalToolResultBudget.encode(.object(["models": .array([]), "large": .string(String(repeating: "x", count: 8000))]), collection: "models", maximumBytes: 4096))
        XCTAssertThrowsError(try LocalToolResultBudget.encode(.object(["wrong": .array([])]), collection: "models", maximumBytes: 4096))
    }
}
