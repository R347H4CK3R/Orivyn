import XCTest
import SQLite3
@testable import JarvisEVO

final class ArchiveAttachmentSupplementPersistenceTests: XCTestCase {
    typealias Source = ArchiveAttachmentSupplement.Source
    func fixture() async throws -> (URL, SQLiteConversationStore, UUID, Conversation, Source, ChatAttachment) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let store = try SQLiteConversationStore(url: url), epoch = try await store.textReceiveEpoch()
        let message = ChatMessage(role: .user, content: "Original visible text")
        let conversation = Conversation(title: "Original", messages: [message])
        let source = Source(archiveSHA256: String(repeating: "a", count: 64), mapSHA256: String(repeating: "b", count: 64), conversationID: conversation.id, messageID: message.id, relativePath: "assets/note.txt", bytes: 4, sha256: String(repeating: "c", count: 64))
        _ = try await store.applyArchiveRestore(jobID: UUID(), archiveSHA256: source.archiveSHA256, expectedEpoch: epoch, conversations: [conversation])
        let id = UUID()
        return (url, store, epoch, conversation, source, ChatAttachment(id: id, name: "note.txt", relativePath: id.uuidString + ".txt", mediaType: "text/plain", byteCount: 4))
    }
    func testAppendsOnlyReviewedAttachmentAndKeepsOriginalReceipt() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let originalReceipt = try await store.archiveRestoreReceipt(archiveSHA256: source.archiveSHA256)
        var edited = conversation; edited.title = "Keep local title"; try await store.save(edited)
        let receipt = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment)
        var expected = edited; expected.messages[0].attachments = [attachment]
        let actual = try await store.load(id: conversation.id); XCTAssertEqual(actual, expected)
        XCTAssertEqual(receipt.attachment, attachment)
        let textReceipt = try await store.archiveRestoreReceipt(archiveSHA256: source.archiveSHA256); XCTAssertEqual(textReceipt, originalReceipt)
        let textReplay = try await store.applyArchiveRestore(jobID: UUID(), archiveSHA256: source.archiveSHA256, expectedEpoch: epoch, conversations: [conversation]); XCTAssertEqual(textReplay, originalReceipt)
        let reopened = try SQLiteConversationStore(url: url)
        let durable = try await reopened.archiveAttachmentSupplementReceipt(source: source, expectedEpoch: epoch); XCTAssertEqual(durable, receipt)
    }
    func testReplayNeverReattachesRemovedAttachment() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let receipt = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment)
        try await store.save(conversation)
        let replay = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment)
        XCTAssertEqual(replay, receipt)
        let actual = try await store.load(id: conversation.id); XCTAssertEqual(actual, conversation)
        var changed = attachment; changed.id = UUID(); changed.relativePath = changed.id.uuidString + ".txt"
        do { _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: changed); XCTFail("Immutable binding") } catch { }
        var rebound = source; rebound.sha256 = String(repeating: "d", count: 64)
        do { _ = try await store.archiveAttachmentSupplementReceipt(source: rebound, expectedEpoch: epoch); XCTFail("Changed source binding") } catch { }
    }
    func testChangedMapCannotReattachSameSourceAfterRemoval() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let receipt = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment)
        try await store.save(conversation)
        var changed = source; changed.mapSHA256 = String(repeating: "d", count: 64)
        do { _ = try await store.archiveAttachmentSupplementReceipt(source: changed, expectedEpoch: epoch); XCTFail("Changed map must conflict, not look like a new source") } catch { }
        var replacement = attachment; replacement.id = UUID(); replacement.relativePath = replacement.id.uuidString + ".txt"
        do { _ = try await store.applyArchiveAttachmentSupplement(source: changed, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: replacement); XCTFail("Changed map cannot reattach") } catch { }
        let actual = try await store.load(id: conversation.id); XCTAssertEqual(actual, conversation)
        let replay = try await store.archiveAttachmentSupplementReceipt(source: source, expectedEpoch: epoch); XCTAssertEqual(replay, receipt)
    }
    func testOriginIsEncodedAndCrossOriginBindingCannotReattach() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(source.origin, .userReviewed)
        let encoded = try JSONEncoder().encode(source)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("userReviewed"))
        XCTAssertEqual(try JSONDecoder().decode(Source.self, from: encoded), source)
        var legacy = source; legacy.origin = .legacyMap
        let receipt = try await store.applyArchiveAttachmentSupplement(source: legacy, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment)
        try await store.save(conversation)
        do { _ = try await store.archiveAttachmentSupplementReceipt(source: source, expectedEpoch: epoch); XCTFail("Cross-origin lookup must conflict") } catch { }
        var replacement = attachment; replacement.id = UUID(); replacement.relativePath = replacement.id.uuidString + ".txt"
        do { _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: replacement); XCTFail("Cross-origin cannot reattach") } catch { }
        let actual = try await store.load(id: conversation.id); XCTAssertEqual(actual, conversation)
        let reopened = try SQLiteConversationStore(url: url)
        let replay = try await reopened.archiveAttachmentSupplementReceipt(source: legacy, expectedEpoch: epoch); XCTAssertEqual(replay, receipt)
    }
    func testUnreleasedVersionOneLedgerFailsClosed() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "DROP TABLE archive_attachment_supplement_state; CREATE TABLE archive_attachment_supplement_state(singleton INTEGER PRIMARY KEY, version INTEGER); INSERT INTO archive_attachment_supplement_state VALUES(1,1)", nil, nil, nil), SQLITE_OK)
        let reopened = try SQLiteConversationStore(url: url)
        do { _ = try await reopened.archiveAttachmentSupplementReceipt(source: source, expectedEpoch: epoch); XCTFail("Unreleased old schema cannot be adopted") } catch { }
        do { _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment); XCTFail("Unreleased old schema cannot mutate") } catch { }
        let actual = try await reopened.load(id: conversation.id); XCTAssertEqual(actual, conversation)
    }
    func testChangedTargetAndNonArchiveMessageRejectWithoutMutation() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        var edited = conversation; edited.messages[0].content = "Local edit"; try await store.save(edited)
        for expected in [conversation.messages[0], edited.messages[0]] {
            do { _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: expected, attachment: attachment); XCTFail("Target must match both reviewed snapshot and archive core") } catch { }
        }
        let actual = try await store.load(id: conversation.id); XCTAssertEqual(actual, edited)
        let missing = try await store.archiveAttachmentSupplementReceipt(source: source, expectedEpoch: epoch); XCTAssertNil(missing)
        let local = Conversation(messages: [ChatMessage(role: .user, content: "Not from archive")]); try await store.save(local)
        var wrong = source; wrong.conversationID = local.id; wrong.messageID = local.messages[0].id
        do { _ = try await store.applyArchiveAttachmentSupplement(source: wrong, expectedEpoch: epoch, expectedMessage: local.messages[0], attachment: attachment); XCTFail("Archive membership required") } catch { }
    }
    func testErasureClearsSupplementReceiptsAndInvalidatesEpoch() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment)
        try await store.delete(id: conversation.id)
        do { _ = try await store.archiveAttachmentSupplementReceipt(source: source, expectedEpoch: epoch); XCTFail("Erased epoch") } catch { }
        do { _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment); XCTFail("Cannot resurrect") } catch { }
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        var statement: OpaquePointer?; XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM archive_attachment_supplements", -1, &statement, nil), SQLITE_OK); defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW); XCTAssertEqual(sqlite3_column_int(statement, 0), 0)
    }
    func testReceiptInsertFailureRollsBackAttachment() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TRIGGER reject_supplement BEFORE INSERT ON archive_attachment_supplements BEGIN SELECT RAISE(ABORT,'injected'); END", nil, nil, nil), SQLITE_OK)
        do { _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment); XCTFail("Injected rollback") } catch { }
        let actual = try await store.load(id: conversation.id); XCTAssertEqual(actual, conversation)
        let receipt = try await store.archiveAttachmentSupplementReceipt(source: source, expectedEpoch: epoch); XCTAssertNil(receipt)
    }
    func testUnsupportedAttachmentAndGlobalIdentityCollisionReject() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        var bad = attachment; bad.mediaType = "application/octet-stream"
        var badPath = attachment; badPath.relativePath = "other.txt"
        var badSize = attachment; badSize.byteCount = 5
        for candidate in [bad, badPath, badSize] {
            do { _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: candidate); XCTFail("Invalid importer output") } catch { }
        }
        var local = Conversation(messages: [ChatMessage(role: .user, content: "Local")]); local.messages[0].attachments = [attachment]; try await store.save(local)
        do { _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment); XCTFail("Asset ID/path already owned") } catch { }
    }
    func testRemovedAssetIdentityCannotBeReboundToAnotherSource() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment)
        try await store.save(conversation)
        var other = source; other.relativePath = "assets/another.txt"
        do { _ = try await store.applyArchiveAttachmentSupplement(source: other, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment); XCTFail("Durable asset identities cannot be reused even after removal") } catch { }
    }
    func testExistingAttachmentsAndAllOtherMessageFieldsArePreserved() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        var local = conversation
        let existingID = UUID()
        let existing = ChatAttachment(id: existingID, name: "Existing", relativePath: existingID.uuidString + ".txt", mediaType: "text/plain", byteCount: 1)
        local.messages[0].attachments = [existing]
        local.messages.append(ChatMessage(role: .assistant, content: "Local additional reply"))
        local.isArchived = true; local.title = "Edited locally"
        try await store.save(local)
        _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: local.messages[0], attachment: attachment)
        local.messages[0].attachments.append(attachment)
        let actual = try await store.load(id: local.id); XCTAssertEqual(actual, local)
    }
    func testCancellationAndMissingTextReceiptCannotAttach() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment)
        }
        do { _ = try await task.value; XCTFail("Cancelled") } catch is CancellationError { }
        let actual = try await store.load(id: conversation.id); XCTAssertEqual(actual, conversation)
        var other = source; other.archiveSHA256 = String(repeating: "f", count: 64)
        do { _ = try await store.applyArchiveAttachmentSupplement(source: other, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment); XCTFail("Text receipt required") } catch { }
    }

    func testLostSupplementReceiptTableIsNotRecreatedOnReopen() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment)
        try await store.save(conversation)
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "DROP TABLE archive_attachment_supplements", nil, nil, nil), SQLITE_OK)
        let reopened = try SQLiteConversationStore(url: url)
        let actual = try await reopened.load(id: conversation.id); XCTAssertEqual(actual, conversation)
        do { _ = try await reopened.archiveAttachmentSupplementReceipt(source: source, expectedEpoch: epoch); XCTFail("Lost receipts must not become an empty fresh ledger") } catch { }
    }

    func testSourceBoundsAndSupportedImporterShapes() async throws {
        let (url, _, _, _, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        for path in ["../escape", "/absolute", "a//b", "a/./b", "a\\b", "a\n", "https:asset", "assets/%61.txt", String(repeating: "a/", count: 524_288)] {
            var bad = source; bad.relativePath = path
            XCTAssertThrowsError(try ArchiveAttachmentSupplement.validate(bad))
        }
        for bytes: UInt64 in [0, 10 * 1024 * 1024 + 1, .max] {
            var bad = source; bad.bytes = bytes
            XCTAssertThrowsError(try ArchiveAttachmentSupplement.validate(bad))
        }
        var bad = source; bad.sha256 = String(repeating: "G", count: 64)
        XCTAssertThrowsError(try ArchiveAttachmentSupplement.validate(bad))
        for (type, suffix) in [("text/plain", "txt"), ("application/pdf", "pdf"), ("image/png", "png"), ("image/jpeg", "jpg"), ("image/heic", "heic"), ("image/heif", "heif")] {
            var candidate = attachment; candidate.mediaType = type; candidate.relativePath = candidate.id.uuidString + "." + suffix
            if candidate.isImage { candidate.previewRelativePath = candidate.id.uuidString + "-preview.jpg" }
            XCTAssertNoThrow(try ArchiveAttachmentSupplement.validate(candidate, source: source))
        }
    }

    func testSupplementDoesNotRewriteUnrelatedPersistedMessageState() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        var local = conversation
        local.messages.append(ChatMessage(role: .assistant, content: "Unrelated persisted checkpoint", state: .streaming))
        try await store.save(local)
        _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: epoch, expectedMessage: local.messages[0], attachment: attachment)
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        var statement: OpaquePointer?; XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT payload FROM conversations", -1, &statement, nil), SQLITE_OK); defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        let bytes = Data(bytes: try XCTUnwrap(sqlite3_column_blob(statement, 0)), count: Int(sqlite3_column_bytes(statement, 0)))
        let actual = try JSONDecoder().decode(Conversation.self, from: bytes)
        local.messages[0].attachments = [attachment]
        XCTAssertEqual(actual, local, "Supplement must not normalize unrelated stored fields")
    }

    func testMixedPreservedReceiptCannotProveTargetWasImported() async throws {
        let (url, store, epoch, conversation, source, attachment) = try await fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        var mixed = source; mixed.archiveSHA256 = String(repeating: "e", count: 64)
        let receipt = try await store.applyArchiveRestore(jobID: UUID(), archiveSHA256: mixed.archiveSHA256, expectedEpoch: epoch, conversations: [conversation, Conversation(title: "New")])
        XCTAssertEqual(receipt.writtenConversations, 1); XCTAssertEqual(receipt.preservedConversations, 1)
        do { _ = try await store.applyArchiveAttachmentSupplement(source: mixed, expectedEpoch: epoch, expectedMessage: conversation.messages[0], attachment: attachment); XCTFail("Legacy counts cannot prove which target was imported") } catch { }
        let actual = try await store.load(id: conversation.id); XCTAssertEqual(actual, conversation)
    }

}
