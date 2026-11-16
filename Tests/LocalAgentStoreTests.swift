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
    func testDuplicateKeysCannotCreateOrOverwriteTask() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString
        let ambiguous = "{\"id\":\"\(id)\",\"revision\":99,\"revision\":1}"
        XCTAssertThrowsError(try store.save(ambiguous, id: id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id + ".json").path))
        let second = UUID().uuidString
        let original = record(second, revision: 2)
        let ambiguousUpdate = "{\"id\":\"\(second)\",\"revision\":99,\"revision\":1}"
        try store.save(original, id: second)
        XCTAssertThrowsError(try store.save(ambiguousUpdate, id: second))
        XCTAssertEqual(Array(try store.load(id: second).utf8), Array(original.utf8))
    }
    func testDuplicateKeysOnDiskRemainUnreadableAndUnchanged() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString, file = root.appendingPathComponent(id + ".json")
        let bytes = Data("{\"id\":\"\(id)\",\"revision\":99,\"revision\":1}".utf8)
        try bytes.write(to: file)
        XCTAssertThrowsError(try store.load(id: id))
        XCTAssertEqual(try store.records().unreadable, 1)
        XCTAssertThrowsError(try store.save(record(id, revision: 100), id: id))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testEscapedAndNestedDuplicateKeysAreRejectedWithoutWriting() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString
        let invalid = [
            #"{"id":"\#(id)","revision":1,"revi\u0073ion":2}"#,
            #"{"id":"\#(id)","id":"\#(id)","revision":1}"#,
            #"{"id":"\#(id)","revision":1,"pending":{"arguments":{"query":"safe","query":"changed"}}}"#,
            #"{"id":"\#(id)","revision":1,"history":[{"outcome":"succeeded","outcome":"failed"}]}"#
        ]
        for raw in invalid {
            XCTAssertThrowsError(try store.save(raw, id: id))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id + ".json").path))
        }
    }
    func testExcessiveNestingIsRejectedBeforeWriting() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString
        let nested = String(repeating: "[", count: 40) + "0" + String(repeating: "]", count: 40)
        let raw = "{\"id\":\"\(id)\",\"revision\":1,\"history\":\(nested)}"
        XCTAssertThrowsError(try store.save(raw, id: id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id + ".json").path))
    }
    func testUniqueLegacyAndCurrentStateKeepExactBytes() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString.lowercased()
        let legacy = #"{"version":1,"id":"\#(id)","goal":"read locally","status":"ready","revision":0,"steps":0,"history":[],"pending":null,"answer":null,"error":null}"#
        let current = #"{"version":1,"id":"\#(id)","goal":"literal \"revision\":1,\"revision\":2 café","status":"ready","revision":1,"steps":0,"history":[],"pending":null,"answer":null,"error":null,"internalReads":0,"resultView":null,"exposedThrough":[]}"#
        try store.save(legacy, id: id)
        XCTAssertEqual(Array(try store.load(id: id).utf8), Array(legacy.utf8))
        try store.save(current, id: id)
        XCTAssertEqual(Array(try store.load(id: id).utf8), Array(current.utf8))
        try store.archive(id: id)
        try store.restore(id: id)
        XCTAssertEqual(Array(try store.load(id: id).utf8), Array(current.utf8))
    }
    func testInvalidInitialRevisionCannotPoisonFutureTaskUpdates() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for field in ["", ",\"revision\":null", ",\"revision\":\"1\"", ",\"revision\":-1", ",\"revision\":true", ",\"revision\":1.5"] {
            let id = UUID().uuidString
            XCTAssertThrowsError(try store.save("{\"id\":\"\(id)\"\(field)}", id: id))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id + ".json").path))
        }
        let id = UUID().uuidString
        try store.save(record(id, revision: 0), id: id)
        try store.save(record(id, revision: 1), id: id)
        XCTAssertEqual(try store.load(id: id), record(id, revision: 1))
    }
    func testInvalidRevisionOnDiskIsUnreadableAndPreserved() async throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString
        let file = root.appendingPathComponent(id + ".json")
        let bytes = Data("{\"id\":\"\(id)\",\"revision\":\"broken\"}".utf8)
        try bytes.write(to: file)
        let batch = try store.records()
        XCTAssertEqual(batch.unreadable, 1)
        XCTAssertTrue(batch.values.isEmpty)
        XCTAssertThrowsError(try store.save(record(id), id: id))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
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

@MainActor final class LocalAgentOriginTests: XCTestCase {
    func testOriginAndTaskAreCommittedTogetherAndSurviveArchive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalAgentStore(directory: root), id = UUID().uuidString, origin = UUID()
        let raw = "{\"id\":\"\(id)\",\"revision\":0}"
        try store.bindOrigin(id: id, conversationID: origin)
        try store.save(raw, id: id)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(id + ".json"))) as? [String: Any])
        XCTAssertEqual(object["chatOrigin"] as? String, origin.uuidString)
        XCTAssertEqual(object["raw"] as? String, raw)
        let reload = try LocalAgentStore(directory: root)
        XCTAssertEqual(try reload.origin(id: id), origin)
        XCTAssertEqual(try reload.load(id: id), raw)
        XCTAssertThrowsError(try reload.bindOrigin(id: id, conversationID: UUID()))
        try reload.archive(id: id); try reload.restore(id: id)
        XCTAssertEqual(try reload.origin(id: id), origin)
        XCTAssertEqual(try reload.load(id: id), raw)
    }
    func testFailedInitialSaveCannotLeaveUnboundTaskAndUpdateKeepsOrigin() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalAgentStore(directory: root), id = UUID().uuidString, origin = UUID()
        try store.bindOrigin(id: id, conversationID: origin)
        XCTAssertThrowsError(try store.save("{}", id: id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(id + ".json").path))
        XCTAssertNil(try LocalAgentStore(directory: root).origin(id: id))
        try store.save("{\"id\":\"\(id)\",\"revision\":0}", id: id)
        let reload = try LocalAgentStore(directory: root)
        let updated = "{\"id\":\"\(id)\",\"revision\":1}"
        try reload.save(updated, id: id)
        XCTAssertEqual(try reload.origin(id: id), origin)
        XCTAssertEqual(try reload.load(id: id), updated)
    }
    func testEnvelopeMissingOriginIsNotLegacyAndIsPreserved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalAgentStore(directory: root), id = UUID().uuidString
        let raw = "{\"id\":\"\(id)\",\"revision\":0}"
        let bytes = try JSONSerialization.data(withJSONObject: ["raw": raw])
        let file = root.appendingPathComponent(id + ".json")
        try bytes.write(to: file)
        XCTAssertThrowsError(try store.origin(id: id))
        XCTAssertThrowsError(try store.load(id: id))
        XCTAssertThrowsError(try store.bindOrigin(id: id, conversationID: UUID()))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
}
