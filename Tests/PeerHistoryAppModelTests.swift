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

    func testCancellationAfterCommitReloadsAndReleasesHistory() async throws {
        let (model, store) = try await fixture()
        let incoming = Conversation(title: "Committed despite cancellation")
        let task = Task { @MainActor in
            try await model.performPeerHistoryReceive {
                try await store.save(incoming)
                withUnsafeCurrentTask { $0?.cancel() }
                try Task.checkCancellation()
            }
        }
        do { try await task.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(model.conversations.map(\.id), [incoming.id])
        let created = await model.newConversation()
        XCTAssertTrue(created)
    }

    func testStalePreflightCannotSweepNewPersistedAttachment() async throws {
        let (model, store) = try await fixture()
        let source = root.appendingPathComponent("retain.txt")
        try Data("Newly persisted private text".utf8).write(to: source)
        let attachment = try model.attachmentService.importFile(at: source)
        let saved = Conversation(messages: [ChatMessage(role: .user, content: "Keep", attachments: [attachment])])
        try await store.save(saved)
        do {
            try await model.performPeerHistoryReceive { XCTFail("Stale receive must not run") }
            XCTFail("Stale preflight must reject")
        } catch {}
        model.clearPendingAttachments()
        XCTAssertNotNil(model.attachmentService.url(for: attachment), "A stale preflight cannot authorize file deletion")
        let bytes = try Data(contentsOf: XCTUnwrap(model.attachmentService.url(for: attachment)))
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "Newly persisted private text")
    }


    func testUnsavedInMemoryTurnRejectsReceiveWithoutDiscardingIt() async throws {
        let (model, store) = try await fixture()
        let created = await model.newConversation()
        XCTAssertTrue(created)
        let id = try XCTUnwrap(model.selectedConversationID)
        model.replaceProviders([ProviderOption(id: "no-inference", title: "No inference", detail: "Test", provider: NoInferenceProvider())])
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("history.sqlite").path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "CREATE TRIGGER fail_history BEFORE INSERT ON conversations BEGIN SELECT RAISE(ABORT, 'test save failure'); END;", nil, nil, nil), SQLITE_OK)
        model.draft = "Unpersisted local turn"
        model.send()
        model.draft = "New composer draft"
        let deadline = Date().addingTimeInterval(3)
        while model.isGenerating && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(model.isGenerating)
        XCTAssertTrue(model.activeConversation?.messages.contains(where: { $0.content == "Unpersisted local turn" }) == true)
        XCTAssertEqual(sqlite3_exec(connection, "DROP TRIGGER fail_history", nil, nil, nil), SQLITE_OK)
        do {
            try await model.performPeerHistoryReceive { XCTFail("Unsaved history must block receive") }
            XCTFail("Unsaved history must reject admission")
        } catch {}
        XCTAssertTrue(model.activeConversation?.messages.contains(where: { $0.content == "Unpersisted local turn" }) == true)
        XCTAssertEqual(model.draft, "New composer draft")
        let saved = try await store.load(id: id)
        XCTAssertTrue(saved?.messages.isEmpty == true)
    }

    func testOutgoingSnapshotRejectsStaleHistoryAndPreservesDraft() async throws {
        let (model, store) = try await fixture()
        let value = Conversation(title: "Not loaded")
        try await store.save(value)
        model.draft = "Keep this"
        do {
            _ = try await model.preparePeerTextSnapshot(ids: [value.id])
            XCTFail("Must not export from stale app history")
        } catch {}
        XCTAssertEqual(model.draft, "Keep this")
        XCTAssertTrue(model.conversations.isEmpty)
    }

    func testOutgoingSnapshotUsesSelectedPersistedConversationOnly() async throws {
        let (model, store) = try await fixture()
        let first = Conversation(title: "Selected")
        let second = Conversation(title: "Not approved")
        try await store.save(first); try await store.save(second)
        await model.bootstrap()
        model.draft = "Unsent draft remains local"
        let snapshot = try await model.preparePeerTextSnapshot(ids: [first.id])
        XCTAssertEqual(snapshot.conversations.map(\.id), [first.id])
        XCTAssertEqual(model.draft, "Unsent draft remains local")
        let created = await model.newConversation()
        XCTAssertTrue(created, "Snapshot must release history ownership")
    }

    func testOutgoingSnapshotCannotRunDuringIncomingReceive() async throws {
        let (model, _) = try await fixture()
        try await model.performPeerHistoryReceive {
            do {
                _ = try await model.preparePeerTextSnapshot(ids: [UUID()])
                XCTFail("Outgoing snapshot must respect incoming history owner")
            } catch {}
        }
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
        // Once the external stale row is removed, a fresh verified preflight
        // must succeed without an unrelated bootstrap or data-discarding reload.
        try await store.delete(id: existing.id)
        let retry = Conversation(title: "Safe retry")
        try await model.performPeerHistoryReceive { try await store.save(retry) }
        XCTAssertEqual(model.conversations.map(\.id), [retry.id])
    }

    // A failed reload must retain the history lock until explicit recovery succeeds.
    func testFailedReloadBlocksMutationsUntilRecovered() async throws {
        let (model, store) = try await fixture()
        let incoming = Conversation(title: "Recoverable")
        model.draft = "Keep my unsent draft"
        let pending = ChatAttachment(name: "pending.txt", relativePath: "pending.txt",
            mediaType: "text/plain", byteCount: 4)
        model.pendingAttachments = [pending]
        XCTAssertFalse(model.needsPeerHistoryRecovery)
        XCTAssertFalse(model.isRecoveringPeerHistory)
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
        XCTAssertTrue(model.needsPeerHistoryRecovery, "Settings must expose recovery after a failed reload")
        XCTAssertFalse(model.isRecoveringPeerHistory)
        let blocked = await model.newConversation()
        XCTAssertFalse(blocked, "Unreadable post-receive history must block mutations")
        do { try await model.recoverPeerHistoryReceive(); XCTFail("Unreadable history must not recover") } catch {}
        XCTAssertTrue(model.needsPeerHistoryRecovery, "A failed recovery must keep the action available")
        XCTAssertFalse(model.isRecoveringPeerHistory, "A failed attempt must permit an explicit retry")
        XCTAssertEqual(model.draft, "Keep my unsent draft")
        XCTAssertEqual(model.pendingAttachments, [pending])
        let stillBlocked = await model.newConversation()
        XCTAssertFalse(stillBlocked, "Failed recovery must retain mutation exclusion")
        try await store.save(incoming)
        try await model.recoverPeerHistoryReceive()
        XCTAssertEqual(model.conversations.map(\.id), [incoming.id])
        XCTAssertFalse(model.needsPeerHistoryRecovery, "Only successful reload removes the recovery action")
        XCTAssertFalse(model.isRecoveringPeerHistory)
        XCTAssertEqual(model.draft, "Keep my unsent draft")
        XCTAssertEqual(model.pendingAttachments, [pending])
        let created = await model.newConversation()
        XCTAssertTrue(created)
    }
}
private enum ReceiveFailure: Error { case lostAcknowledgement }

private struct NoInferenceProvider: AIProvider {
    let id = "no-inference"
    let displayName = "No inference"
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        XCTFail("The failed initial save must prevent provider execution")
        throw ReceiveFailure.lostAcknowledgement
    }
}
