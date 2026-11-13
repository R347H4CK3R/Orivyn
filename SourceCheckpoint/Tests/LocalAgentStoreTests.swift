import XCTest
@testable import JarvisEVO

@MainActor final class LocalAgentStoreTests: XCTestCase {
    private func fixture(capacity: Int = 100) throws -> (URL, LocalAgentStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (root, try LocalAgentStore(directory: root, maximumRecords: capacity))
    }
    private func record(_ id: String, revision: Int = 1, goal: String = "goal") -> String {
        "{\"id\":\"\(id)\",\"revision\":\(revision),\"goal\":\"\(goal)\"}"
    }
    func testSameRevisionRequiresIdenticalBytesNotCanonicalUnicodeEquivalence() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString
        let original = record(id, goal: "\u{e9}"), altered = record(id, goal: "e\u{301}")
        XCTAssertNotEqual(Array(original.utf8), Array(altered.utf8))
        try store.save(original, id: id)
        XCTAssertThrowsError(try store.save(altered, id: id))
        XCTAssertEqual(Array(try store.load(id: id).utf8), Array(original.utf8))
    }
    func testRevisionRollbackAndChangedSameRevisionDoNotOverwriteState() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString, initial = record(UUID().uuidString)
        XCTAssertThrowsError(try store.save(initial, id: id))
        let value = record(id, revision: 2)
        try store.save(value, id: id); try store.save(value, id: id)
        XCTAssertThrowsError(try store.save(record(id, revision: 1), id: id))
        XCTAssertThrowsError(try store.save(record(id, revision: 2, goal: "changed"), id: id))
        XCTAssertEqual(try store.load(id: id), value)
    }
    func testArchiveFreesCapacityAndRestorationPreservesExactBytes() async throws {
        let (root, store) = try fixture(capacity: 1); defer { try? FileManager.default.removeItem(at: root) }
        let first = UUID().uuidString, second = UUID().uuidString, value = record(first, goal: "café")
        try store.save(value, id: first)
        XCTAssertThrowsError(try store.save(record(second), id: second))
        try store.archive(id: first)
        XCTAssertEqual(try store.records().total, 0)
        XCTAssertEqual(try store.archivedRecords().values, [value])
        try store.save(record(second), id: second)
        XCTAssertThrowsError(try store.restore(id: first))
        XCTAssertEqual(try store.archivedRecords().values, [value])
        try store.archive(id: second); try store.restore(id: first)
        XCTAssertEqual(Array(try store.load(id: first).utf8), Array(value.utf8))
    }
    func testCorruptRecordIsCountedUnreadableAndNeverDeleted() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(UUID().uuidString + ".json")
        let bytes = Data("broken".utf8); try bytes.write(to: file)
        let records = try store.records()
        XCTAssertEqual(records.total, 1); XCTAssertEqual(records.unreadable, 1)
        XCTAssertTrue(records.values.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testSymlinkRecordCannotReadOrOverwriteAnotherFile() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString, target = root.appendingPathComponent("protected.txt")
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent(id + ".json").path, withDestinationPath: target.path)
        XCTAssertThrowsError(try store.load(id: id))
        XCTAssertThrowsError(try store.save(record(id), id: id))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep")
    }
}
