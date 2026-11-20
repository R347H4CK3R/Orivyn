import XCTest
import SQLite3
@testable import JarvisEVO

@MainActor
final class ConversationMetadataTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "ConversationMetadataTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    private func fixture() throws -> (AppModel, SQLiteConversationStore, MetadataTokenSource) {
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let model = AppModel(offlineAutoSelection: false, store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: root.appendingPathComponent("Models")), defaults: defaults)
        let source = MetadataTokenSource()
        let provider = MetadataProvider(source: source)
        model.replaceProviders([ProviderOption(id: provider.id, title: "Test", detail: "Test only", provider: provider)])
        return (model, store, source)
    }
    private func execute(_ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(root.appendingPathComponent("history.sqlite").path, &database) == SQLITE_OK else { throw TestError.database }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw TestError.database }
    }
    private func waitFor(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw TestError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    func testFailedNewConversationReturnsFailureAndPreservesComposer() async throws {
        let (model, store, _) = try fixture()
        model.draft = "Keep unsent draft"
        try execute("CREATE TRIGGER fail_insert BEFORE INSERT ON conversations BEGIN SELECT RAISE(FAIL, 'test failure'); END;")
        let failed = await model.newConversation()
        XCTAssertFalse(failed)
        XCTAssertEqual(model.draft, "Keep unsent draft")
        XCTAssertNil(model.selectedConversationID)
        XCTAssertTrue(model.conversations.isEmpty)
        try execute("DROP TRIGGER fail_insert;")
        let saved = await model.newConversation()
        XCTAssertTrue(saved)
        let disk = try await store.list(includeArchived: true)
        XCTAssertEqual(disk.count, 1)
        XCTAssertEqual(model.selectedConversationID, disk.first?.id)
    }

    func testFailedRenamePreservesUIAndDiskThenRetryCommits() async throws {
        let (model, store, _) = try fixture()
        await model.newConversation()
        let before = try XCTUnwrap(model.activeConversation)
        try execute("CREATE TRIGGER fail_metadata BEFORE UPDATE ON conversations BEGIN SELECT RAISE(ABORT, 'test failure'); END;")
        let failed = await model.rename(before.id, to: "Must not appear yet")
        XCTAssertFalse(failed)
        XCTAssertEqual(model.activeConversation, before)
        let storedBefore = try await store.load(id: before.id)
        XCTAssertEqual(storedBefore, before)
        try execute("DROP TRIGGER fail_metadata")
        let saved = await model.rename(before.id, to: "  Committed name  ")
        XCTAssertTrue(saved)
        XCTAssertEqual(model.activeConversation?.title, "Committed name")
        let storedAfter = try await store.load(id: before.id)
        XCTAssertEqual(storedAfter?.title, "Committed name")
        XCTAssertEqual(storedAfter?.messages, before.messages)
    }
    func testFailedArchivePreservesUIAndDiskThenRestoreCommits() async throws {
        let (model, store, _) = try fixture()
        await model.newConversation()
        let before = try XCTUnwrap(model.activeConversation)
        try execute("CREATE TRIGGER fail_metadata BEFORE UPDATE ON conversations BEGIN SELECT RAISE(ABORT, 'test failure'); END;")
        let failed = await model.archive(before.id, archived: true)
        XCTAssertFalse(failed)
        XCTAssertEqual(model.activeConversation, before)
        let storedBefore = try await store.load(id: before.id)
        XCTAssertEqual(storedBefore, before)
        try execute("DROP TRIGGER fail_metadata")
        let saved = await model.archive(before.id, archived: true)
        XCTAssertTrue(saved)
        let archived = try await store.load(id: before.id)
        XCTAssertEqual(archived?.isArchived, true)
        let restored = await model.archive(before.id, archived: false)
        XCTAssertTrue(restored)
        let unarchived = try await store.load(id: before.id)
        XCTAssertEqual(unarchived?.isArchived, false)
    }
    func testStreamingTargetRejectsMetadataChangesWithoutDroppingTokens() async throws {
        let (model, store, source) = try fixture()
        model.draft = "Question"
        model.send()
        try await waitFor { await source.subscribed }
        let id = try XCTUnwrap(model.selectedConversationID)
        let title = model.activeConversation?.title
        let renamed = await model.rename(id, to: "Race")
        let archived = await model.archive(id, archived: true)
        XCTAssertFalse(renamed); XCTAssertFalse(archived)
        XCTAssertTrue(model.isGenerating)
        await source.emit("Preserved answer")
        await source.finish()
        try await waitFor { !model.isGenerating }
        let stored = try await store.load(id: id)
        XCTAssertEqual(stored?.title, title)
        XCTAssertEqual(stored?.isArchived, false)
        XCTAssertEqual(stored?.messages.last?.content, "Preserved answer")
        XCTAssertEqual(stored?.messages.last?.state, .complete)
    }
    func testDifferentConversationMetadataDoesNotStopActiveStream() async throws {
        let (model, store, source) = try fixture()
        await model.newConversation()
        let idleID = try XCTUnwrap(model.selectedConversationID)
        await model.newConversation()
        let streamingID = try XCTUnwrap(model.selectedConversationID)
        model.draft = "Question"; model.send()
        try await waitFor { await source.subscribed }
        let renamed = await model.rename(idleID, to: "Other conversation")
        let archived = await model.archive(idleID, archived: true)
        XCTAssertTrue(renamed); XCTAssertTrue(archived)
        XCTAssertTrue(model.isGenerating)
        await source.emit("Unaffected response"); await source.finish()
        try await waitFor { !model.isGenerating }
        let streamed = try await store.load(id: streamingID)
        XCTAssertEqual(streamed?.messages.last?.content, "Unaffected response")
        let idle = try await store.load(id: idleID)
        XCTAssertEqual(idle?.title, "Other conversation")
        XCTAssertEqual(idle?.isArchived, true)
    }
    func testInvalidTargetAndEmptyTitleReturnFalse() async throws {
        let (model, _, _) = try fixture()
        await model.newConversation()
        let id = try XCTUnwrap(model.selectedConversationID)
        let blank = await model.rename(id, to: " \n")
        let missingName = await model.rename(UUID(), to: "Missing")
        let missingArchive = await model.archive(UUID(), archived: true)
        XCTAssertFalse(blank); XCTAssertFalse(missingName); XCTAssertFalse(missingArchive)
    }
    private enum TestError: Error { case database, timeout }
}

private struct MetadataProvider: AIProvider {
    let id = "metadata-test"
    let displayName = "Metadata test"
    let source: MetadataTokenSource
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> { await source.subscribe() }
}
private actor MetadataTokenSource {
    private let pair = AsyncThrowingStream<String, Error>.makeStream()
    private(set) var subscribed = false
    func subscribe() -> AsyncThrowingStream<String, Error> { subscribed = true; return pair.stream }
    func emit(_ value: String) { pair.continuation.yield(value) }
    func finish() { pair.continuation.finish() }
}
