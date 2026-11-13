import XCTest
@testable import JarvisEVO

@MainActor
final class LocalAgentCoreTests: XCTestCase {
    func testModelCannotRequestAnExternalToolAndInterruptedStateDoesNotReplay() throws {
        let core = try LocalAgentCore()
        let state = try core.call("create", ["Which app is this?", UUID().uuidString])
        XCTAssertThrowsError(try core.call("acceptDecision", [state, #"{"type":"tool","name":"send_email","arguments":{}}"#]))
        let running = try core.call("acceptDecision", [state, #"{"type":"tool","name":"get_app_info","arguments":{}}"#])
        XCTAssertEqual(try core.snapshot(running).status, "running")
        let recovered = try core.call("recover", [running])
        XCTAssertEqual(try core.snapshot(recovered).status, "interrupted")
        XCTAssertThrowsError(try core.call("acceptDecision", [recovered, #"{"type":"answer","text":"Invented completion"}"#]))
    }
    func testAgentStorePreservesProtectedStatesAndRejectsMismatchedIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = try LocalAgentCore()
        let store = try LocalAgentStore(directory: root)
        let state = try core.call("create", ["List installed models", UUID().uuidString])
        let snapshot = try core.snapshot(state)
        try store.save(state, id: snapshot.id)
        XCTAssertEqual(try store.load(id: snapshot.id), state)
        XCTAssertThrowsError(try store.save(state, id: "../../wrong"))
        XCTAssertThrowsError(try store.save(state, id: UUID().uuidString))
    }
    func testStoreRejectsRollbackAndConflictingSameRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = try LocalAgentCore(), store = try LocalAgentStore(directory: root)
        let original = try core.call("create", ["Read app info", UUID().uuidString])
        let id = try core.snapshot(original).id
        let advanced = try core.call("acceptDecision", [original, #"{"type":"tool","name":"get_app_info","arguments":{}}"#])
        try store.save(advanced, id: id)
        XCTAssertThrowsError(try store.save(original, id: id))
        let conflicting = try core.call("acceptDecision", [original, #"{"type":"tool","name":"list_models","arguments":{}}"#])
        XCTAssertThrowsError(try store.save(conflicting, id: id))
        XCTAssertEqual(try store.load(id: id), advanced)
    }
    func testUnreadableTaskIsPreservedWithoutHidingValidRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = try LocalAgentCore(), store = try LocalAgentStore(directory: root)
        let good = try core.call("create", ["Read app info", UUID().uuidString])
        try store.save(good, id: core.snapshot(good).id)
        let damaged = root.appendingPathComponent(UUID().uuidString + ".json")
        try Data("not JSON".utf8).write(to: damaged)
        let batch = try store.records()
        XCTAssertEqual(batch.values, [good])
        XCTAssertEqual(batch.unreadable, 1)
        XCTAssertEqual(try Data(contentsOf: damaged), Data("not JSON".utf8))
    }
    func testAgentGrammarForcesFirstToolWithoutWeakeningLaterValidation() throws {
        XCTAssertTrue(try LocalAgentGrammar.load(requireTool: true).hasPrefix("root ::= tool\n"))
        XCTAssertTrue(try LocalAgentGrammar.load(requireTool: false).hasPrefix("root ::= tool | read-result | answer\n"))
    }

    func testArchiveFreesCapacityAndRestoreNeverOverwrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = try LocalAgentCore(), store = try LocalAgentStore(directory: root)
        var first = "", firstID = ""
        for index in 0..<100 {
            let value = try core.call("create", ["Task \(index)", UUID().uuidString])
            let id = try core.snapshot(value).id
            try store.save(value, id: id)
            if index == 0 { first = value; firstID = id }
        }
        let extra = try core.call("create", ["New task", UUID().uuidString])
        let extraID = try core.snapshot(extra).id
        XCTAssertThrowsError(try store.save(extra, id: extraID))
        try store.archive(id: firstID)
        XCTAssertEqual(try store.archivedRecords().values, [first])
        XCTAssertThrowsError(try store.save(first, id: firstID), "Stale session must not resurrect an archived task")
        try store.save(extra, id: extraID)
        XCTAssertThrowsError(try store.restore(id: firstID))
        XCTAssertEqual(try store.archivedRecords().values, [first])
        try store.archive(id: extraID)
        try store.restore(id: firstID)
        XCTAssertEqual(try store.load(id: firstID), first)
        XCTAssertThrowsError(try store.archive(id: "../../escape"))
    }

    func testLegacyPagingMigrationPersistsWithMonotonicRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = try LocalAgentCore(), store = try LocalAgentStore(directory: root)
        let fresh = try core.call("create", ["Read app info", UUID().uuidString])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(fresh.utf8)) as? [String: Any])
        legacy.removeValue(forKey: "internalReads"); legacy.removeValue(forKey: "resultView")
        let old = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys]), encoding: .utf8))
        let id = try core.snapshot(old).id
        try store.save(old, id: id)
        let migrated = try core.call("recover", [old])
        XCTAssertGreaterThan(try core.snapshot(migrated).revision, try core.snapshot(old).revision)
        try store.save(migrated, id: id)
        XCTAssertEqual(try core.call("recover", [migrated]), migrated)
        XCTAssertEqual(try store.load(id: id), migrated)
    }

}
