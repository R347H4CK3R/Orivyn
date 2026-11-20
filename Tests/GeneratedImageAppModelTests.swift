import XCTest
import UIKit
import SQLite3
@testable import JarvisEVO

@MainActor
final class GeneratedImageAppModelTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "Orivyn.GeneratedImageTests.\(UUID().uuidString)"; defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root)
    }
    func testAcceptedImagePersistsSeparatelyWithoutSendingOrChangingComposer() async throws {
        let (model, store, _) = try fixture()
        await model.newConversation(); let selected = model.selectedConversationID
        model.draft = "Keep this draft"; model.selectedProviderID = "manual-choice"
        let pending = try model.attachmentService.importImage(data: png(), suggestedName: "pending.png")
        model.pendingAttachments = [pending]
        let stager = try staging(); let owned = try stage(stager)
        let task = try XCTUnwrap(model.acceptGeneratedImage(owned, concept: "  Blue kite  ", stager: stager))
        XCTAssertTrue(model.isSavingGeneratedImage)
        XCTAssertFalse(model.canSend, "Do not overlap a text model with accepted-image decoding")
        await task.value
        XCTAssertFalse(model.isSavingGeneratedImage); XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(model.selectedConversationID, selected); XCTAssertEqual(model.draft, "Keep this draft")
        XCTAssertEqual(model.pendingAttachments, [pending]); XCTAssertEqual(model.selectedProviderID, "manual-choice")
        let saved = try await store.list(includeArchived: true)
        let result = try XCTUnwrap(saved.first { $0.id != selected })
        XCTAssertEqual(result.messages.first?.content, "  Blue kite  ")
        let image = try XCTUnwrap(result.messages.last?.attachments.first)
        XCTAssertNotNil(model.attachmentService.url(for: image)); XCTAssertNotNil(model.attachmentService.previewURL(for: image))
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        let reopened = AppModel(offlineAutoSelection: false, store: store, attachmentService: model.attachmentService,
            modelStore: try LocalModelStore(root: root.appendingPathComponent("Models")), defaults: defaults)
        await reopened.bootstrap()
        XCTAssertTrue(reopened.conversations.contains { $0.id == result.id })
        XCTAssertNotNil(reopened.attachmentService.url(for: image))
    }
    func testDeleteAllDuringImportCannotResurrectImageOrLeaveFiles() async throws {
        let (model, store, held) = try fixture(held: true)
        let stager = try staging(); let owned = try stage(stager)
        let task = try XCTUnwrap(model.acceptGeneratedImage(owned, concept: "Blue kite", stager: stager))
        try await waitFor { await held.isHolding }
        await model.deleteAllContent()
        XCTAssertEqual(try files(model).count, 2, "Do not sweep while importer owns new files")
        await held.release(); await task.value
        let saved = try await store.list(includeArchived: true)
        XCTAssertTrue(saved.isEmpty); XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertTrue(try files(model).isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }
    func testDuplicateAcceptanceIsRefusedAndOnlyItsOwnStagingIsDiscarded() async throws {
        let (model, store, held) = try fixture(held: true)
        let stager = try staging(); let first = try stage(stager); let second = try stage(stager)
        let task = try XCTUnwrap(model.acceptGeneratedImage(first, concept: "First", stager: stager))
        try await waitFor { await held.isHolding }
        XCTAssertNil(model.acceptGeneratedImage(second, concept: "Second", stager: stager))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        await held.release(); await task.value
        let saved = try await store.list(includeArchived: true)
        XCTAssertEqual(saved.count, 1); XCTAssertEqual(saved.first?.messages.first?.content, "First")
    }
    func testInvalidConceptDiscardsStagingWithoutStartingImport() throws {
        let (model, _, _) = try fixture(); let stager = try staging()
        for concept in [" ", String(repeating: "x", count: 1025), "a\u{0}b"] {
            let owned = try stage(stager)
            XCTAssertNil(model.acceptGeneratedImage(owned, concept: concept, stager: stager))
            XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        }
        XCTAssertFalse(model.isSavingGeneratedImage); XCTAssertTrue(try files(model).isEmpty)
    }
    func testInvalidImageNeverPublishesConversationAndCleansStaging() async throws {
        let (model, store, _) = try fixture(); let stager = try staging()
        let source = root.appendingPathComponent("invalid.png"); try Data([1,2,3]).write(to: source)
        let owned = try stager.stage(from: source)
        let task = try XCTUnwrap(model.acceptGeneratedImage(owned, concept: "Blue kite", stager: stager)); await task.value
        let saved = try await store.list(includeArchived: true)
        XCTAssertTrue(saved.isEmpty); XCTAssertTrue(try files(model).isEmpty)
        XCTAssertNotNil(model.errorMessage); XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }
    func testRealSQLiteFailureDoesNotPublishOrLeakImportedImage() async throws {
        let (model, _, held) = try fixture(held: true); let stager = try staging(); let owned = try stage(stager)
        let task = try XCTUnwrap(model.acceptGeneratedImage(owned, concept: "Blue kite", stager: stager))
        try await waitFor { await held.isHolding }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("test.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "DROP TABLE conversations", nil, nil, nil), SQLITE_OK)
        await held.release(); await task.value
        XCTAssertTrue(model.conversations.isEmpty); XCTAssertTrue(try files(model).isEmpty)
        XCTAssertFalse(model.isSavingGeneratedImage); XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }
    func testRepeatedSameURLCallbackCannotDiscardActiveImport() async throws {
        let (model, store, held) = try fixture(held: true); let stager = try staging(); let owned = try stage(stager)
        let task = try XCTUnwrap(model.acceptGeneratedImage(owned, concept: "First", stager: stager))
        try await waitFor { await held.isHolding }
        XCTAssertNil(model.acceptGeneratedImage(owned, concept: "Duplicate", stager: stager))
        XCTAssertTrue(FileManager.default.fileExists(atPath: owned.path))
        await held.release(); await task.value
        let saved = try await store.list(includeArchived: true)
        XCTAssertEqual(saved.count, 1); XCTAssertEqual(saved.first?.messages.first?.content, "First")
    }
    func testStartupReclaimsOnlyRecognizedOwnedFilesAndPreservesUnexpectedEntries() throws {
        let (model, _, _) = try fixture(); let stager = try staging(); let owned = try stage(stager)
        let unexpected = stager.directory.appendingPathComponent(".atomic-stale")
        try Data([1]).write(to: unexpected)
        let subdirectory = stager.directory.appendingPathComponent("unknown")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: false)
        let symlink = stager.directory.appendingPathComponent(UUID().uuidString + ".png")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: root.appendingPathComponent("source.png"))
        model.configureGeneratedImages(directory: stager.directory)
        XCTAssertNotNil(model.generatedImageStager)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unexpected.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: subdirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlink.path))
    }
    func testHistoryDeletionDuringSQLiteSaveIsRefusedUntilCommitFinishes() async throws {
        let (model, store, held) = try fixture(held: true); let stager = try staging(); let owned = try stage(stager)
        let task = try XCTUnwrap(model.acceptGeneratedImage(owned, concept: "Keep committed image", stager: stager))
        try await waitFor { await held.isHolding }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("test.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil); sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        await held.release()
        try await waitFor { model.isSavingGeneratedImageRecord }
        await model.deleteAllContent()
        XCTAssertTrue(model.errorMessage?.contains("accepted image") == true)
        XCTAssertEqual(sqlite3_exec(db, "COMMIT", nil, nil, nil), SQLITE_OK)
        await task.value
        let saved = try await store.list(includeArchived: true)
        XCTAssertEqual(saved.count, 1); XCTAssertEqual(model.conversations.count, 1)
    }
    func testCommittedGeneratedImageRelinquishesRollbackOwnershipBeforeHistoryLoad() async throws {
        let (model, store, _) = try fixture()
        let stager = try staging(); let owned = try stage(stager)
        let task = try XCTUnwrap(model.acceptGeneratedImage(owned, concept: "Blue square", stager: stager))
        await task.value
        let savedRows = try await store.list(includeArchived: true)
        let saved = try XCTUnwrap(savedRows.first)
        let image = try XCTUnwrap(saved.messages.last?.attachments.first)
        await model.delete(saved.id)
        // A successful save transferred the fresh-file lease. Until a complete
        // history read, rollback cannot assume another persisted branch is absent.
        XCTAssertNotNil(model.attachmentService.url(for: image))
        await model.bootstrap()
        XCTAssertTrue(try files(model).isEmpty)
    }

    private func fixture(held: Bool = false) throws -> (AppModel, SQLiteConversationStore, GeneratedImageHoldingImporter) {
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("test.sqlite"))
        let service = try AttachmentService(directory: root.appendingPathComponent("Attachments"))
        let importer = GeneratedImageHoldingImporter(service: service, hold: held)
        let model = AppModel(offlineAutoSelection: false, store: store, attachmentService: service, modelStore: try LocalModelStore(root: root.appendingPathComponent("Models")), defaults: defaults, attachmentImporter: importer)
        return (model, store, importer)
    }
    private func staging() throws -> GeneratedImageStaging { try .init(directory: root.appendingPathComponent("Staging")) }
    private func stage(_ stager: GeneratedImageStaging) throws -> URL {
        let source = root.appendingPathComponent("source.png"); try png().write(to: source); return try stager.stage(from: source)
    }
    private func png() -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).pngData { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
    }
    private func files(_ model: AppModel) throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: model.attachmentService.directory.path) }
    private func waitFor(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await condition()) { guard ContinuousClock.now < deadline else { throw CancellationError() }; try await Task.sleep(for: .milliseconds(5)) }
    }
}
private actor GeneratedImageHoldingImporter: AttachmentImporting {
    let importer: LocalAttachmentImporter
    let hold: Bool
    var continuation: CheckedContinuation<Void, Never>?
    var isHolding: Bool { continuation != nil }
    init(service: AttachmentService, hold: Bool) { importer = LocalAttachmentImporter(service: service); self.hold = hold }
    func importAttachment(_ source: AttachmentImportSource) async throws -> ChatAttachment {
        let result = try await importer.importAttachment(source)
        if hold { await withCheckedContinuation { continuation = $0 } }
        return result
    }
    func release() { continuation?.resume(); continuation = nil }
}
