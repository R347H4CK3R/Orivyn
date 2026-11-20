import XCTest
@testable import JarvisEVO

/// Native production components with synthetic local files and isolated SQLite.
/// Does not simulate a Files-provider grant or assert actual picker selection.
@MainActor
final class BackupSelectedFileIntegrationTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BackupSelectedFile-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "BackupSelectedFile." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private struct Fixture {
        let model: AppModel
        let store: SQLiteConversationStore
        let file: URL
        let local: Conversation
        let incoming: Conversation
    }

    private func fixture() async throws -> Fixture {
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("destination.sqlite"))
        let source = try SQLiteConversationStore(url: root.appendingPathComponent("source.sqlite"))
        let local = Conversation(title: "Local newer history", messages: [ChatMessage(role: .user, content: "Keep my local message")])
        var incoming = local
        incoming.title = "Selected backup history"
        incoming.messages = [ChatMessage(role: .user, content: "Replacement backup message")]
        try await store.save(local)
        try await source.save(incoming)
        let bytes = try await source.exportData()
        let file = root.appendingPathComponent("controlled-backup.json")
        try bytes.write(to: file, options: .atomic)
        let model = AppModel(offlineAutoSelection: false, store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: root.appendingPathComponent("Models")), defaults: defaults)
        model.draft = "Unsent controlled draft"
        return Fixture(model: model, store: store, file: file, local: local, incoming: incoming)
    }

    private func select(_ file: URL, policy: BackupImportPolicy,
                        state: inout BackupImportConfirmation) throws -> BackupImportConfirmation.Request? {
        let token = try XCTUnwrap(state.beginSelection(policy: policy))
        let captured = try XCTUnwrap(state.finishSelection(token))
        return state.select(file, policy: captured)
    }

    func testSelectedReplacementWaitsThenCommitsOnlyOnce() async throws {
        let f = try await fixture()
        var state = BackupImportConfirmation()
        XCTAssertNil(try select(f.file, policy: .replaceMatching, state: &state))
        let before = try await f.store.load(id: f.local.id)
        XCTAssertEqual(before, f.local, "Selection alone must not write.")
        XCTAssertEqual(state.pending?.url, f.file)
        let request = try XCTUnwrap(state.confirm())
        XCTAssertNil(state.confirm(), "A second confirmation cannot produce another import request.")
        await f.model.importHistory(from: request.url, policy: request.policy)
        XCTAssertNil(f.model.errorMessage)
        let after = try await f.store.load(id: f.local.id)
        XCTAssertEqual(after, f.incoming)
        XCTAssertEqual(f.model.conversations.first?.id, f.local.id)
        XCTAssertEqual(f.model.draft, "Unsent controlled draft")
        XCTAssertNil(state.pending)
    }

    func testSelectedReplacementCancelLeavesLocalDataAndFileUnchanged() async throws {
        let f = try await fixture()
        let bytes = try Data(contentsOf: f.file)
        var state = BackupImportConfirmation()
        XCTAssertNil(try select(f.file, policy: .replaceMatching, state: &state))
        state.cancel()
        XCTAssertNil(state.confirm())
        let after = try await f.store.load(id: f.local.id)
        XCTAssertEqual(after, f.local)
        XCTAssertEqual(try Data(contentsOf: f.file), bytes)
        XCTAssertEqual(f.model.draft, "Unsent controlled draft")
    }

    func testSelectedPreserveLocalSkipsConflictingBackup() async throws {
        let f = try await fixture()
        var state = BackupImportConfirmation()
        let request = try XCTUnwrap(select(f.file, policy: .preserveLocal, state: &state))
        XCTAssertNil(state.pending)
        await f.model.importHistory(from: request.url, policy: request.policy)
        XCTAssertNil(f.model.errorMessage)
        let after = try await f.store.load(id: f.local.id)
        XCTAssertEqual(after, f.local)
        let all = try await f.store.list(includeArchived: true)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(f.model.draft, "Unsent controlled draft")
    }

    func testNavigationInvalidationRejectsLateSelectedFile() async throws {
        let f = try await fixture()
        var state = BackupImportConfirmation()
        let token = try XCTUnwrap(state.beginSelection(policy: .replaceMatching))
        state.invalidate()
        XCTAssertNil(state.finishSelection(token))
        XCTAssertNil(state.select(f.file, policy: .replaceMatching))
        XCTAssertNil(state.confirm())
        let after = try await f.store.load(id: f.local.id)
        XCTAssertEqual(after, f.local)
    }

    func testCorruptedSelectedFileFailsWithoutReplacingHistory() async throws {
        let f = try await fixture()
        try Data("not a backup".utf8).write(to: f.file)
        var state = BackupImportConfirmation()
        XCTAssertNil(try select(f.file, policy: .replaceMatching, state: &state))
        let request = try XCTUnwrap(state.confirm())
        await f.model.importHistory(from: request.url, policy: request.policy)
        XCTAssertNotNil(f.model.errorMessage)
        let after = try await f.store.load(id: f.local.id)
        XCTAssertEqual(after, f.local)
        XCTAssertNil(state.confirm())
    }
}
