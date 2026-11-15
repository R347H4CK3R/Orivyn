import XCTest
import SQLite3
@testable import JarvisEVO

@MainActor
final class PeerHistoryAppModelTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "Orivyn.PeerHistoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "orivyn.automaticModels")
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    private func fixture() async throws -> (AppModel, SQLiteConversationStore) {
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let model = AppModel(store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: root.appendingPathComponent("Models")), defaults: defaults)
        await model.bootstrap()
        return (model, store)
    }

    // Omitting reconciliation leaves a committed conversation invisible to the app.
    func testCommittedReceiveReloadsHistoryWithoutChangingComposer() async throws {
        let (model, store) = try await fixture()
        model.draft = "Unsent local draft"
        let pending = ChatAttachment(name: "draft.txt", relativePath: "draft.txt", mediaType: "text/plain", byteCount: 5)
        model.pendingAttachments = [pending]
        let incoming = Conversation(title: "Received")
        try await model.performPeerHistoryReceive { try await store.save(incoming) }
        XCTAssertEqual(model.conversations.map(\.id), [incoming.id])
        XCTAssertEqual(model.draft, "Unsent local draft")
        XCTAssertEqual(model.pendingAttachments, [pending])
    }

    // A transport error can occur after the durable commit, so success-only reload is wrong.
    func testLostAcknowledgementStillReloadsCommittedHistory() async throws {
        let (model, store) = try await fixture()
        let incoming = Conversation(title: "Committed before lost acknowledgement")
        do {
            try await model.performPeerHistoryReceive {
                try await store.save(incoming)
                throw ReceiveFailure.lostAcknowledgement
            }
            XCTFail("The transport error must propagate")
        } catch ReceiveFailure.lostAcknowledgement {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(model.conversations.map(\.id), [incoming.id])
    }

    // Without admission ownership another history mutation can race a suspended receive.
    func testReceiveOwnsHistoryUntilReconciliationCompletes() async throws {
        let (model, store) = try await fixture()
        let incoming = Conversation(title: "Only accepted receive")
        try await model.performPeerHistoryReceive {
            let created = await model.newConversation()
            XCTAssertFalse(created, "History mutation must be excluded during receive")
            do {
                try await model.performPeerHistoryReceive { XCTFail("Nested receive must not execute") }
                XCTFail("Nested receive must reject admission")
            } catch {}
            try await store.save(incoming)
        }
        XCTAssertEqual(model.conversations.map(\.id), [incoming.id])
        let createdAfter = await model.newConversation()
        XCTAssertTrue(createdAfter, "Successful reconciliation must release history ownership")
    }

    // An old in-memory snapshot must not overwrite newer database history after receive.
    func testStaleHistoryRejectsReceiveWithoutDiscardingLocalState() async throws {
        let (model, store) = try await fixture()
        let existing = Conversation(title: "Changed outside the loaded snapshot")
        try await store.save(existing)
        model.draft = "Preserve draft"
        do {
            try await model.performPeerHistoryReceive {
                try await store.save(Conversation(title: "Must not import"))
            }
            XCTFail("Stale history must reject receive")
        } catch {}
        let saved = try await store.list(includeArchived: true)
        XCTAssertEqual(saved.map(\.id), [existing.id])
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertEqual(model.draft, "Preserve draft")
    }

    // A failed reload must retain the history lock until explicit recovery succeeds.
    func testFailedReloadBlocksMutationsUntilRecovered() async throws {
        let (model, store) = try await fixture()
        let incoming = Conversation(title: "Recoverable")
        do {
            try await model.performPeerHistoryReceive {
                try await store.save(incoming)
                var connection: OpaquePointer?
                XCTAssertEqual(sqlite3_open(self.root.appendingPathComponent("history.sqlite").path, &connection), SQLITE_OK)
                defer { sqlite3_close(connection) }
                XCTAssertEqual(sqlite3_exec(connection, "UPDATE conversations SET payload = x'00'", nil, nil, nil), SQLITE_OK)
                throw ReceiveFailure.lostAcknowledgement
            }
            XCTFail("Reload failure must propagate")
        } catch {}
        let blocked = await model.newConversation()
        XCTAssertFalse(blocked, "Unreadable post-receive history must block mutations")
        try await store.save(incoming)
        try await model.recoverPeerHistoryReceive()
        XCTAssertEqual(model.conversations.map(\.id), [incoming.id])
        let created = await model.newConversation()
        XCTAssertTrue(created)
    }
}
private enum ReceiveFailure: Error { case lostAcknowledgement }
