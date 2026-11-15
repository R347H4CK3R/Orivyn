import XCTest
@testable import JarvisEVO

/// Runs on Apple hosts with real file coordination and SQLite. Does not test AppModel or Files UI.
@MainActor
final class BackupHostChainTests: XCTestCase {
    private func fixture() async throws -> (SQLiteConversationStore, URL, Conversation, Conversation) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackupChain-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let destination = try SQLiteConversationStore(url: root.appendingPathComponent("destination.sqlite"))
        let source = try SQLiteConversationStore(url: root.appendingPathComponent("source.sqlite"))
        let local = Conversation(title: "Local", messages: [ChatMessage(role: .user, content: "New local message")])
        var incoming = local
        incoming.title = "Backup"
        incoming.messages = [ChatMessage(role: .user, content: "Older backup message")]
        try await destination.save(local)
        try await source.save(incoming)
        let url = root.appendingPathComponent("backup.json")
        let bytes = try await source.exportData()
        try bytes.write(to: url, options: .atomic)
        return (destination, url, local, incoming)
    }
    private func selection(_ url: URL, policy: BackupImportPolicy, state: inout BackupImportConfirmation) throws -> BackupImportConfirmation.Request? {
        let token = try XCTUnwrap(state.beginSelection(policy: policy))
        let captured = try XCTUnwrap(state.finishSelection(token))
        return state.select(url, policy: captured)
    }
    func testConfirmedSelectionCoordinatesReadAndReplacesExactRecordOnce() async throws {
        let (store, url, local, incoming) = try await fixture()
        var state = BackupImportConfirmation()
        XCTAssertNil(try selection(url, policy: .replaceMatching, state: &state))
        let before = try await store.load(id: local.id)
        XCTAssertEqual(before, local)
        let request = try XCTUnwrap(state.confirm())
        XCTAssertNil(state.confirm())
        let data = try await BackupFileReader.read(request.url)
        _ = try await store.importData(data, policy: request.policy)
        let after = try await store.load(id: local.id)
        XCTAssertEqual(after, incoming)
        let all = try await store.list(includeArchived: true)
        XCTAssertEqual(all.count, 1)
    }
    func testCancelledReplacementAndPreserveSelectionKeepLocalRecord() async throws {
        let (store, url, local, _) = try await fixture()
        let bytes = try Data(contentsOf: url)
        var state = BackupImportConfirmation()
        XCTAssertNil(try selection(url, policy: .replaceMatching, state: &state))
        state.cancel()
        XCTAssertNil(state.confirm())
        let request = try XCTUnwrap(selection(url, policy: .preserveLocal, state: &state))
        let data = try await BackupFileReader.read(request.url)
        _ = try await store.importData(data, policy: request.policy)
        let after = try await store.load(id: local.id)
        XCTAssertEqual(after, local)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testCorruptedConfirmedFileCannotReplaceLocalHistory() async throws {
        let (store, url, local, _) = try await fixture()
        try Data("corrupted".utf8).write(to: url)
        var state = BackupImportConfirmation()
        XCTAssertNil(try selection(url, policy: .replaceMatching, state: &state))
        let request = try XCTUnwrap(state.confirm())
        let data = try await BackupFileReader.read(request.url)
        do {
            _ = try await store.importData(data, policy: request.policy)
            XCTFail("Corrupted backup was accepted")
        } catch { }
        let after = try await store.load(id: local.id)
        XCTAssertEqual(after, local)
        XCTAssertNil(state.confirm())
    }
}
