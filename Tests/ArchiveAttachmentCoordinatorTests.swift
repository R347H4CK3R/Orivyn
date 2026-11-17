import XCTest
import CryptoKit
import ImageIO
import PDFKit
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
    private func fixture(zip: String = "manual-attachments", path: String = "assets/reviewed-note.txt") async throws -> (AppModel, SQLiteConversationStore, ArchiveRestoreView.Review, ArchiveRestoreService.AttachmentCandidate) {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: zip, withExtension: "zip"))
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let model = AppModel(store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: root.appendingPathComponent("Models")), defaults: defaults)
        model.configureLocalWork(directory: root)
        let review = try await model.prepareArchiveRestore(source, progress: { _ in })
        _ = try await model.commitArchiveRestore(review, progress: { _ in })
        let page = try await model.retainedArchiveAttachmentFiles(review, offset: 0)
        let messages = try await model.retainedArchiveAttachmentMessages(review, offset: 0, query: "Synthetic ZIP acceptance question.")
        let file = try XCTUnwrap(page.items.first { $0.relativePath == path })
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

    private func commitDAT(path: String, expectedType: String) async throws -> (AppModel, ChatAttachment) {
        let (model, store, review, candidate) = try await fixture(zip: "dat-attachments", path: path)
        XCTAssertEqual(candidate.source.relativePath, path)
        XCTAssertEqual(candidate.source.origin, .userReviewed)
        let snapshot = try await model.reviewArchiveAttachment(review, candidate: candidate)
        XCTAssertTrue(snapshot.attachments.isEmpty, "Explicit selection is read-only")
        let noReceipt = try await store.archiveAttachmentSupplementReceipt(source: candidate.source, expectedEpoch: candidate.expectedEpoch)
        XCTAssertNil(noReceipt)
        _ = try await model.commitArchiveAttachment(review, candidate: candidate, expectedMessage: snapshot, progress: { _ in })
        let receiptValue = try await store.archiveAttachmentSupplementReceipt(source: candidate.source, expectedEpoch: candidate.expectedEpoch)
        let receipt = try XCTUnwrap(receiptValue)
        XCTAssertEqual(receipt.source, candidate.source, "Receipt retains exact original .dat path and bytes, not classified staging identity")
        let attachment = receipt.attachment
        XCTAssertEqual(attachment.mediaType, expectedType)
        XCTAssertEqual(attachment.name, path.split(separator: "/").last.map(String.init))
        let original = try XCTUnwrap(model.attachmentService.url(for: attachment))
        let data = try Data(contentsOf: original)
        XCTAssertEqual(UInt64(data.count), candidate.source.bytes)
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), candidate.source.sha256)
        let saved = try await store.load(id: candidate.source.conversationID)
        XCTAssertEqual(try XCTUnwrap(saved).messages.first { $0.id == candidate.source.messageID }?.attachments, [attachment])
        _ = try await model.commitArchiveAttachment(review, candidate: candidate, expectedMessage: snapshot, progress: { _ in })
        let replayed = try await store.load(id: candidate.source.conversationID)
        XCTAssertEqual(replayed, saved)
        let reopened = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let durable = try await reopened.load(id: candidate.source.conversationID)
        XCTAssertEqual(durable, saved)
        let durableReceipt = try await reopened.archiveAttachmentSupplementReceipt(source: candidate.source, expectedEpoch: candidate.expectedEpoch)
        XCTAssertEqual(durableReceipt, receipt)
        XCTAssertFalse(try FileManager.default.subpathsOfDirectory(atPath: root.path).contains { $0.contains("/attachment-staging/") }, "No staged copy survives committed import")
        return (model, attachment)
    }
    func testSelectedDATTextUsesNativeImporterAndPreservesOriginalReceiptIdentity() async throws {
        let (model, attachment) = try await commitDAT(path: "assets/reviewed-text.dat", expectedType: "text/plain")
        XCTAssertEqual(attachment.extractedText, "Synthetic reviewed DAT text.\n")
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(model.attachmentService.url(for: attachment)), encoding: .utf8), "Synthetic reviewed DAT text.\n")
    }
    func testSelectedDATImageUsesNativeDecoderAndTrustedPreview() async throws {
        let (model, attachment) = try await commitDAT(path: "assets/reviewed-image.dat", expectedType: "image/png")
        let original = try XCTUnwrap(model.attachmentService.url(for: attachment))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(original as CFURL, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 2); XCTAssertEqual(decoded.height, 2)
        let preview = try XCTUnwrap(model.attachmentService.previewURL(for: attachment))
        let previewSource = try XCTUnwrap(CGImageSourceCreateWithURL(preview as CFURL, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(previewSource, 0, nil))
    }
    func testSelectedDATPDFUsesNativePDFDecoder() async throws {
        let (model, attachment) = try await commitDAT(path: "assets/reviewed-pdf.dat", expectedType: "application/pdf")
        let url = try XCTUnwrap(model.attachmentService.url(for: attachment))
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue((attachment.extractedText ?? "").contains("Synthetic DAT PDF acceptance."))
    }
    func testMalformedSelectedDATRejectsWithoutReceiptOrOwnedFileLeak() async throws {
        let (model, store, review, initial) = try await fixture(zip: "dat-attachments", path: "assets/malformed-image.dat")
        for path in ["assets/malformed-image.dat", "assets/malformed-pdf.dat"] {
        let files = try await model.retainedArchiveAttachmentFiles(review, offset: 0)
        let messages = try await model.retainedArchiveAttachmentMessages(review, offset: 0, query: "Synthetic ZIP acceptance question.")
        let file = try XCTUnwrap(files.items.first { $0.relativePath == path })
        let target = try XCTUnwrap(messages.items.first { $0.messageID == initial.source.messageID })
        let selected = try await model.reviewArchiveAttachment(review, file: file, message: target)
        let candidate = selected.candidate
        let snapshot = try await model.reviewArchiveAttachment(review, candidate: candidate)
        let before = try await store.load(id: candidate.source.conversationID)
        let beforeFiles = try FileManager.default.subpathsOfDirectory(atPath: model.attachmentService.directory.path).sorted()
        do {
            _ = try await model.commitArchiveAttachment(review, candidate: candidate, expectedMessage: snapshot, progress: { _ in })
            XCTFail("Malformed declared media must not fall back to text or commit")
        } catch { }
        let after = try await store.load(id: candidate.source.conversationID)
        XCTAssertEqual(after, before)
        let receipt = try await store.archiveAttachmentSupplementReceipt(source: candidate.source, expectedEpoch: candidate.expectedEpoch)
        XCTAssertNil(receipt)
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: model.attachmentService.directory.path).sorted(), beforeFiles)
        XCTAssertEqual(candidate.source.relativePath, path)
        XCTAssertFalse(try FileManager.default.subpathsOfDirectory(atPath: root.path).contains { $0.contains("/attachment-staging/") }, "Rejected import leaves no owned staging file")
        }
    }

}
