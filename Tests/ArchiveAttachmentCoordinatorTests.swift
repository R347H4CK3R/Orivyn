import XCTest
@testable import JarvisEVO

/// Synthetic native importer + SQLite integration. No user ZIP or network.
@MainActor
final class ArchiveAttachmentCoordinatorTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "ArchiveAttachmentCoordinator." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    private func fixture() async throws -> (AppModel, SQLiteConversationStore, ArchiveRestoreView.Review, ArchiveRestoreService.AttachmentCandidate) {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "manual-attachments", withExtension: "zip"))
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let model = AppModel(store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: root.appendingPathComponent("Models")), defaults: defaults)
        model.configureLocalWork(directory: root)
        let review = try await model.prepareArchiveRestore(source, progress: { _ in })
        _ = try await model.commitArchiveRestore(review, progress: { _ in })
        let page = try await model.retainedArchiveAttachmentFiles(review, offset: 0)
        let messages = try await model.retainedArchiveAttachmentMessages(review, offset: 0, query: "Synthetic ZIP acceptance question.")
        let file = try XCTUnwrap(page.items.first { $0.relativePath == "assets/reviewed-note.txt" })
        let selected = try XCTUnwrap(messages.items.first)
        let selection = try await model.reviewArchiveAttachment(review, file: file, message: selected)
        return (model, store, review, selection.candidate)
    }
    func testSelectionIsReadOnlyThenExplicitCommitPersistsExactFileAndReplaysWithoutDuplication() async throws {
        let (model, store, review, candidate) = try await fixture()
        let snapshot = try await model.reviewArchiveAttachment(review, candidate: candidate)
        XCTAssertTrue(snapshot.attachments.isEmpty)
        let before = try await store.load(id: candidate.source.conversationID)
        XCTAssertTrue(try XCTUnwrap(before).messages.allSatisfy { $0.attachments.isEmpty })
        _ = try await model.commitArchiveAttachment(review, candidate: candidate, expectedMessage: snapshot, progress: { _ in })
        let savedValue = try await store.load(id: candidate.source.conversationID)
        let saved = try XCTUnwrap(savedValue)
        let message = try XCTUnwrap(saved.messages.first { $0.id == candidate.source.messageID })
        let attachment = try XCTUnwrap(message.attachments.first)
        XCTAssertEqual(message.attachments.count, 1)
        XCTAssertEqual(attachment.name, "reviewed-note.txt")
        let file = try XCTUnwrap(model.attachmentService.url(for: attachment))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Synthetic reviewed attachment.\n")
        _ = try await model.commitArchiveAttachment(review, candidate: candidate, expectedMessage: snapshot, progress: { _ in })
        let replayed = try await store.load(id: saved.id)
        XCTAssertEqual(replayed, saved)
        let reopened = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let durable = try await reopened.load(id: saved.id)
        XCTAssertEqual(durable, saved)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Synthetic reviewed attachment.\n")
    }
    func testChangedReviewedMessageRejectsWithoutAddingFilesOrOverwritingEdit() async throws {
        let (model, store, review, candidate) = try await fixture()
        let snapshot = try await model.reviewArchiveAttachment(review, candidate: candidate)
        let editValue = try await store.load(id: candidate.source.conversationID)
        var edited = try XCTUnwrap(editValue)
        let index = try XCTUnwrap(edited.messages.firstIndex { $0.id == candidate.source.messageID })
        edited.messages[index].content = "Local edit must survive"
        try await store.save(edited)
        do {
            _ = try await model.commitArchiveAttachment(review, candidate: candidate, expectedMessage: snapshot, progress: { _ in })
            XCTFail("Changed review accepted")
        } catch { }
        let saved = try await store.load(id: edited.id)
        XCTAssertEqual(saved, edited)
        XCTAssertFalse((try FileManager.default.contentsOfDirectory(atPath: model.attachmentService.directory.path)).contains { $0.hasSuffix(".txt") })
    }
    func testHistoricalReceiptDoesNotReattachUserRemovedFile() async throws {
        let (model, store, review, candidate) = try await fixture()
        let snapshot = try await model.reviewArchiveAttachment(review, candidate: candidate)
        _ = try await model.commitArchiveAttachment(review, candidate: candidate, expectedMessage: snapshot, progress: { _ in })
        let savedValue = try await store.load(id: candidate.source.conversationID)
        var saved = try XCTUnwrap(savedValue)
        let index = try XCTUnwrap(saved.messages.firstIndex { $0.id == candidate.source.messageID })
        let attachment = try XCTUnwrap(saved.messages[index].attachments.first)
        saved.messages[index].attachments = []
        try await store.save(saved)
        model.attachmentService.remove(attachment)
        _ = try await model.commitArchiveAttachment(review, candidate: candidate, expectedMessage: snapshot, progress: { _ in })
        let replayed = try await store.load(id: saved.id)
        XCTAssertEqual(replayed, saved)
        XCTAssertNil(model.attachmentService.url(for: attachment))
    }

}
