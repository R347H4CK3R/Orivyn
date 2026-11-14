import XCTest
import SQLite3
@testable import JarvisEVO

@MainActor
final class ConversationBranchTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "Orivyn.BranchTests.\(UUID().uuidString)"; defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root)
    }
    private func fixture() async throws -> (AppModel, SQLiteConversationStore, Conversation, BranchProvider) {
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let original = Conversation(title: "Original", messages: [ChatMessage(role: .user, content: "First question"), ChatMessage(role: .assistant, content: "First answer"), ChatMessage(role: .user, content: "Later question"), ChatMessage(role: .assistant, content: "Later answer")])
        try await store.save(original)
        let model = AppModel(store: store, attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")), modelStore: try LocalModelStore(root: root.appendingPathComponent("Models")), defaults: defaults)
        await model.bootstrap()
        let provider = BranchProvider()
        model.replaceProviders([ProviderOption(id: provider.id, title: "Fixture", detail: "Controlled test", provider: provider)])
        model.selectedConversationID = original.id
        return (model, store, original, provider)
    }
    private func finish(_ model: AppModel) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while model.isGenerating {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    func testEditBranchesOnlyThroughSelectedUserAndPreservesDraftAndOriginal() async throws {
        let (model, store, original, provider) = try await fixture()
        model.draft = "Unsent separate draft"
        let accepted = await model.editAndBranch(messageID: original.messages[0].id, text: "Edited first question", sourceConversationID: original.id)
        XCTAssertTrue(accepted); try await finish(model)
        XCTAssertEqual(model.draft, "Unsent separate draft")
        let unchanged = try await store.load(id: original.id)
        XCTAssertEqual(unchanged, original)
        XCTAssertNotEqual(model.activeConversation?.id, original.id)
        XCTAssertEqual(model.activeConversation?.messages.map(\.content), ["Edited first question", "Controlled answer"])
        let request = await provider.lastRequest
        XCTAssertEqual(request?.messages.map(\.content), ["Edited first question"])
    }
    func testRegenerateRejectsUserTargetAndUsesCorrectPrecedingTurn() async throws {
        let (model, store, original, provider) = try await fixture()
        let rejected = await model.regenerate(messageID: original.messages[2].id, sourceConversationID: original.id)
        XCTAssertFalse(rejected)
        let accepted = await model.regenerate(messageID: original.messages[3].id, sourceConversationID: original.id)
        XCTAssertTrue(accepted); try await finish(model)
        let request = await provider.lastRequest
        XCTAssertEqual(request?.messages.map(\.content), ["First question", "First answer", "Later question"])
        let persistedOriginal = try await store.load(id: original.id)
        XCTAssertEqual(persistedOriginal, original)
    }
    func testUnavailableProviderDoesNotCreateMisleadingBranch() async throws {
        let (model, store, original, _) = try await fixture()
        model.replaceProviders([])
        let edit = await model.editAndBranch(messageID: original.messages[0].id, text: "Kept edit", sourceConversationID: original.id)
        let regenerate = await model.regenerate(messageID: original.messages[1].id, sourceConversationID: original.id)
        XCTAssertFalse(edit); XCTAssertFalse(regenerate)
        let saved = try await store.list(includeArchived: true)
        XCTAssertEqual(saved.count, 1)
    }
    func testStaleOriginCannotBranchAnotherConversationWithSharedMessageIDs() async throws {
        let (model, store, original, _) = try await fixture()
        let other = try original.branching(through: original.messages[0].id)
        try await store.save(other); await model.bootstrap(); model.selectedConversationID = other.id
        let accepted = await model.branch(through: original.messages[0].id, sourceConversationID: original.id)
        XCTAssertFalse(accepted)
        XCTAssertEqual(model.selectedConversationID, other.id)
    }
    func testFailedBranchSaveReturnsFalseWithoutLosingOriginalOrComposer() async throws {
        let (model, store, original, _) = try await fixture()
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("history.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TRIGGER fail_branch BEFORE INSERT ON conversations BEGIN SELECT RAISE(ABORT, 'test failure'); END;", nil, nil, nil), SQLITE_OK)
        model.draft = "Keep composer"
        let accepted = await model.editAndBranch(messageID: original.messages[0].id, text: "Retain editor text", sourceConversationID: original.id)
        XCTAssertFalse(accepted); XCTAssertEqual(model.draft, "Keep composer")
        XCTAssertEqual(model.selectedConversationID, original.id)
        let persisted = try await store.load(id: original.id)
        XCTAssertEqual(persisted, original)
    }
}
private actor BranchProvider: AIProvider {
    nonisolated let id = "branch-fixture"
    nonisolated let displayName = "Controlled branch fixture"
    private(set) var lastRequest: GenerationRequest?
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        lastRequest = request
        return AsyncThrowingStream { continuation in continuation.yield("Controlled answer"); continuation.finish() }
    }
}
