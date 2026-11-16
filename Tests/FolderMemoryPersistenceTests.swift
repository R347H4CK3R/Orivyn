import XCTest
import SQLite3
@testable import JarvisEVO

final class FolderMemoryPersistenceTests: XCTestCase {
    func testAdditiveImportDeduplicatesAcrossRunsAndPreservesHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("test.sqlite"))
        let original = MemoryNote(content: "Keep this")
        try await store.saveMemory(original)
        let incoming = MemoryNote(content: "Imported text")
        _ = try await store.importMemoryNotes([incoming, MemoryNote(content: "Keep this")])
        _ = try await store.importMemoryNotes([MemoryNote(content: "Imported text")])
        let all = try await store.memories()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(original))
    }
    func testInvalidBatchDoesNotPartiallySave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("test.sqlite"))
        do {
            _ = try await store.importMemoryNotes([MemoryNote(content: "Valid"), MemoryNote(content: String(repeating: "x", count: 4001))])
            XCTFail("Must reject invalid batch")
        } catch { }
        let all = try await store.memories()
        XCTAssertTrue(all.isEmpty)
    }
    func testMidTransactionFailureRollsBackEarlierNotes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.sqlite")
        let store = try SQLiteConversationStore(url: url)
        let original = MemoryNote(content: "Original")
        try await store.saveMemory(original)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TRIGGER reject_second BEFORE INSERT ON memory WHEN NEW.content = 'Reject me' BEGIN SELECT RAISE(ABORT, 'injected write failure'); END;", nil, nil, nil), SQLITE_OK)
        do { _ = try await store.importMemoryNotes([MemoryNote(content: "Would be first"), MemoryNote(content: "Reject me")]); XCTFail("Must roll back") } catch { }
        let remaining = try await store.memories()
        XCTAssertEqual(remaining, [original])
    }

}
