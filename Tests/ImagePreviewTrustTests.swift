import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import JarvisEVO

@MainActor
final class ImagePreviewTrustTests: XCTestCase {
    private var root: URL!
    private var service: AttachmentService!
    private var store: SQLiteConversationStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        service = try AttachmentService(directory: root.appendingPathComponent("Attachments"))
        store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    // Checks the actual UI share payload, not the action's label or a claimed filename.
    func testTrustedPreviewIsBoundedMetadataStrippedAndSurvivesServiceReopen() throws {
        let image = try importPhoto()
        let original = try XCTUnwrap(service.url(for: image))
        let originalProperties = try properties(original)
        XCTAssertNotNil(originalProperties[kCGImagePropertyGPSDictionary])
        XCTAssertNotNil((originalProperties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertEqual((originalProperties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 3000)
        let preview = try XCTUnwrap(service.previewURL(for: image))
        XCTAssertNotEqual(preview, original)
        try assertSanitizedBoundedJPEG(preview)
        let reopened = try AttachmentService(directory: service.directory)
        XCTAssertEqual(reopened.previewURL(for: image), preview)
    }

    func testReimportCannotReplaceCleanPreviewWithItsGPSBearingOriginal() async throws {
        let image = try importPhoto()
        let original = try await saveAndExport([image])
        var forged = image
        forged.previewRelativePath = image.relativePath
        XCTAssertNil(service.previewURL(for: forged), "The resolver must independently reject unvalidated metadata")
        try await assertRejectedBackup(original, replacingFirstWith: forged)
        try assertSanitizedBoundedJPEG(XCTUnwrap(service.previewURL(for: image)))
    }

    func testReimportCannotSwapInAnotherOriginalOrPreview() async throws {
        let first = try importPhoto()
        let second = try importPhoto()
        let original = try await saveAndExport([first, second])
        for path in [second.relativePath, try XCTUnwrap(second.previewRelativePath)] {
            var forged = first
            forged.previewRelativePath = path
            XCTAssertNil(service.previewURL(for: forged))
            try await assertRejectedBackup(original, replacingFirstWith: forged)
        }
        try assertSanitizedBoundedJPEG(XCTUnwrap(service.previewURL(for: first)))
        try assertSanitizedBoundedJPEG(XCTUnwrap(service.previewURL(for: second)))
    }

    func testForgedIDsPathsAndMediaTypesCannotResolveOtherImageBytes() async throws {
        let first = try importPhoto()
        let second = try importPhoto()
        let original = try await saveAndExport([first, second])
        var unknownID = first
        unknownID.id = UUID()
        var wrongID = first
        wrongID.id = second.id
        var swappedPair = first
        swappedPair.relativePath = second.relativePath
        swappedPair.previewRelativePath = second.previewRelativePath
        var wrongType = first
        wrongType.mediaType = "image/png"
        var disguisedDocument = first
        disguisedDocument.mediaType = "text/plain"
        disguisedDocument.previewRelativePath = nil
        for forged in [unknownID, wrongID, swappedPair, wrongType, disguisedDocument] {
            XCTAssertNil(service.previewURL(for: forged))
            XCTAssertNil(service.url(for: forged))
            try await assertRejectedBackup(original, replacingFirstWith: forged)
        }
    }

    func testStructurallyValidButForgedSizeFailsPrivateOwnershipCheckAfterRestore() async throws {
        let image = try importPhoto()
        var backup = try await saveAndExport([image])
        var forged = image
        forged.byteCount += 1
        backup.conversations[0].messages[0].attachments[0] = forged
        // A backup from another device cannot be checked against local bytes during generic decoding.
        try await store.importData(JSONEncoder().encode(backup))
        let restoredConversation = try await store.load(id: backup.conversations[0].id)
        let restored = try XCTUnwrap(restoredConversation?.messages[0].attachments[0])
        XCTAssertNil(service.previewURL(for: restored))
        XCTAssertNil(service.url(for: restored))
        XCTAssertNotNil(service.previewURL(for: image))
    }

    // Correct-looking names alone cannot turn a metadata-bearing original into a trusted clean file.
    func testFilesWithoutPrivateImportProvenanceNeverResolveAsCleanPreview() async throws {
        let bytes = try photoBytes()
        let id = UUID()
        let originalName = id.uuidString + ".jpg"
        let previewName = id.uuidString + "-preview.jpg"
        try bytes.write(to: service.directory.appendingPathComponent(originalName))
        try bytes.write(to: service.directory.appendingPathComponent(previewName))
        let forged = ChatAttachment(id: id, name: "Old or forged image", relativePath: originalName,
                                    mediaType: "image/jpeg", byteCount: bytes.count, previewRelativePath: previewName)
        let backup = try await saveAndExport([forged])
        try await store.importData(JSONEncoder().encode(backup))
        XCTAssertNil(service.previewURL(for: forged))
        XCTAssertNil(service.url(for: forged))
    }

    func testMissingPreviewDoesNotFallBackToOriginal() throws {
        var image = try importPhoto()
        let original = try XCTUnwrap(service.url(for: image))
        let preview = try XCTUnwrap(service.previewURL(for: image))
        try FileManager.default.removeItem(at: preview)
        XCTAssertNil(service.previewURL(for: image))
        XCTAssertEqual(service.url(for: image), original)
        image.previewRelativePath = nil
        XCTAssertNil(service.previewURL(for: image))
        XCTAssertEqual(service.url(for: image), original)
    }

    func testPreviewSizeMismatchFailsClosedEvenWithAnExistingImportRecord() throws {
        let image = try importPhoto()
        let originalBytes = try Data(contentsOf: XCTUnwrap(service.url(for: image)))
        let preview = try XCTUnwrap(service.previewURL(for: image))
        XCTAssertNotEqual(originalBytes.count, try Data(contentsOf: preview).count)
        try originalBytes.write(to: preview, options: .atomic)
        XCTAssertNil(service.previewURL(for: image))
    }

    func testSymlinkProvenanceDirectoryCannotAuthorizeOrReceiveNewImports() throws {
        let image = try importPhoto()
        let records = provenanceDirectory()
        let moved = root.appendingPathComponent("MovedRecords")
        try FileManager.default.moveItem(at: records, to: moved)
        try FileManager.default.createSymbolicLink(at: records, withDestinationURL: moved)
        XCTAssertNil(service.previewURL(for: image))
        XCTAssertNil(service.url(for: image))
        let before = try FileManager.default.contentsOfDirectory(atPath: service.directory.path)
        XCTAssertThrowsError(try importPhoto())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: service.directory.path).sorted(), before.sorted())
    }

    func testSymlinkOrOversizedRecordCannotAuthorizePreview() throws {
        let image = try importPhoto()
        let record = provenanceDirectory().appendingPathComponent(image.id.uuidString + ".json")
        let moved = root.appendingPathComponent("MovedRecord.json")
        try FileManager.default.moveItem(at: record, to: moved)
        try FileManager.default.createSymbolicLink(at: record, withDestinationURL: moved)
        XCTAssertNil(service.previewURL(for: image))
        try FileManager.default.removeItem(at: record)
        try Data(repeating: 0x20, count: 4097).write(to: record)
        XCTAssertNil(service.previewURL(for: image))
        try Data("{".utf8).write(to: record)
        XCTAssertNil(service.previewURL(for: image))
    }

    func testOriginalOnlyReferenceRetainsItsOwnershipRecordWithoutInventingPreview() throws {
        var image = try importPhoto()
        try service.removeUnreferenced(keeping: [image.relativePath])
        image.previewRelativePath = nil
        XCTAssertNotNil(service.url(for: image))
        XCTAssertNil(service.previewURL(for: image))
    }

    func testDuplicateImageIDsAndCollidingPathsAreRejectedBeforeMerge() async throws {
        let first = try importPhoto()
        let second = try importPhoto()
        let original = try await saveAndExport([first, second])
        var duplicate = original
        duplicate.conversations[0].messages[0].attachments = [first, first]
        try await assertRejected(duplicate)
        var colliding = original
        colliding.conversations[0].messages[0].attachments[1].relativePath = first.relativePath
        try await assertRejected(colliding)
        let saved = try await store.load(id: original.conversations[0].id)
        XCTAssertEqual(saved, original.conversations[0])
    }

    func testConflictingImageIdentityAcrossBackupConversationsIsRejectedAtomically() async throws {
        let image = try importPhoto()
        let original = try await saveAndExport([image])
        var conflict = image
        conflict.mediaType = "image/png"
        conflict.relativePath = image.id.uuidString + ".png"
        var backup = original
        backup.conversations.append(Conversation(messages: [ChatMessage(role: .user, content: "Conflict", attachments: [conflict])]))
        try await assertRejected(backup)
        let values = try await store.list(includeArchived: true)
        XCTAssertEqual(values, original.conversations)
    }

    func testExactSharedImageIdentityAcrossBranchesRemainsTrusted() async throws {
        let image = try importPhoto()
        var backup = try await saveAndExport([image])
        let shared = Conversation(title: "Branch", messages: backup.conversations[0].messages)
        backup.conversations.append(shared)
        try await store.importData(JSONEncoder().encode(backup))
        let saved = try await store.load(id: shared.id)
        let restored = try XCTUnwrap(saved?.messages.first?.attachments.first)
        XCTAssertEqual(restored.id, image.id)
        XCTAssertEqual(service.previewURL(for: restored), service.previewURL(for: image))
        try assertSanitizedBoundedJPEG(XCTUnwrap(service.previewURL(for: restored)))
    }

    func testConflictingPartialImportLeavesAllConversationsAndMemoriesUnchanged() async throws {
        let image = try importPhoto()
        let first = Conversation(title: "First", messages: [ChatMessage(role: .user, content: "Photo", attachments: [image])])
        var branch = try first.branching(through: XCTUnwrap(first.messages.first?.id))
        branch.isArchived = true // Hidden history must participate in the same identity invariant.
        let untouched = Conversation(title: "Untouched")
        let note = MemoryNote(content: "Keep this memory")
        let untouchedNote = MemoryNote(content: "Also keep this memory")
        try await store.importData(JSONEncoder().encode(ConversationBackup(
            conversations: [first, branch, untouched], memories: [note, untouchedNote])))
        let before = try await store.list(includeArchived: true)
        let beforeNotes = try await store.memories()

        var replacement = first
        replacement.title = "Must not replace the saved title"
        replacement.messages[0].attachments[0].byteCount += 1
        var replacementNote = note
        replacementNote.content = "Must not replace the saved memory"
        let inserted = Conversation(title: "Must not insert")
        try await assertRejected(ConversationBackup(conversations: [inserted, replacement],
            memories: [replacementNote, MemoryNote(content: "Must not insert this memory")]))

        try await assertStoreContains(before, memories: beforeNotes)
        let reopened = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let reopenedValues = try await reopened.list(includeArchived: true)
        let reopenedNotes = try await reopened.memories()
        XCTAssertEqual(reopenedValues, before)
        XCTAssertEqual(reopenedNotes, beforeNotes)
        try await assertFullExportRestores()
        try assertSanitizedBoundedJPEG(XCTUnwrap(service.previewURL(for: image)))
    }

    func testConsistentPartialImportKeepsUntouchedSharedBranchAndMergesMemory() async throws {
        let image = try importPhoto()
        let first = Conversation(title: "First", messages: [ChatMessage(role: .user, content: "Photo", attachments: [image])])
        let branch = try first.branching(through: XCTUnwrap(first.messages.first?.id))
        let note = MemoryNote(content: "Original memory")
        try await store.importData(JSONEncoder().encode(ConversationBackup(conversations: [first, branch], memories: [note])))

        var replacement = first
        replacement.title = "Edited first conversation"
        replacement.messages[0].attachments[0].extractedText = "An edited OCR transcript"
        replacement.messages[0].attachments[0].previewRelativePath = nil
        var replacementNote = note
        replacementNote.content = "Edited memory"
        let inserted = Conversation(title: "A legitimate additional conversation")
        try await store.importData(JSONEncoder().encode(ConversationBackup(
            conversations: [replacement, inserted], memories: [replacementNote])))

        try await assertStoreContains([replacement, branch, inserted], memories: [replacementNote])
        try await assertFullExportRestores()
        try assertSanitizedBoundedJPEG(XCTUnwrap(service.previewURL(for: image)))
    }

    func testImportCanConsistentlyReplaceEverySharedIdentityWithoutComparingSupersededRows() async throws {
        let image = try importPhoto()
        var first = Conversation(title: "First", messages: [ChatMessage(role: .user, content: "Photo", attachments: [image])])
        var branch = try first.branching(through: XCTUnwrap(first.messages.first?.id))
        let untouched = Conversation(title: "Unrelated history stays")
        try await store.importData(JSONEncoder().encode(ConversationBackup(conversations: [first, branch, untouched], memories: [])))

        first.messages[0].attachments[0].byteCount += 1
        branch.messages[0].attachments[0].byteCount += 1
        first.title = "Replacement first"
        branch.title = "Replacement branch"
        let note = MemoryNote(content: "A valid merged memory")
        // Either per-row save would temporarily conflict with an old row. Validate the final state instead.
        try await store.importData(JSONEncoder().encode(ConversationBackup(conversations: [branch, first], memories: [note])))

        try await assertStoreContains([first, branch, untouched], memories: [note])
        try await assertFullExportRestores()
        XCTAssertNil(service.previewURL(for: first.messages[0].attachments[0]), "Storage consistency must not grant private file provenance")
        XCTAssertNotNil(service.previewURL(for: image))
    }

    func testConflictingNormalSaveCannotReplaceOneSharedBranch() async throws {
        let image = try importPhoto()
        let first = Conversation(title: "First", messages: [ChatMessage(role: .user, content: "Photo", attachments: [image])])
        var branch = try first.branching(through: XCTUnwrap(first.messages.first?.id))
        branch.isArchived = true
        let note = MemoryNote(content: "Retain memory")
        try await store.save(first)
        try await store.save(branch)
        try await store.saveMemory(note)

        var replacement = first
        replacement.title = "Must not update"
        replacement.messages[0].attachments[0].byteCount += 1
        do {
            try await store.save(replacement)
            XCTFail("Conflicting shared image identity was saved")
        } catch ConversationError.unsafeAttachment { } catch { XCTFail("Unexpected error: \(error)") }

        try await assertStoreContains([first, branch], memories: [note])
        try await assertFullExportRestores()
        // A rejected save must release its transaction and leave the store writable.
        var validUpdate = first
        validUpdate.title = "A valid later edit"
        try await store.save(validUpdate)
        try await assertStoreContains([validUpdate, branch], memories: [note])
    }

    func testConflictingNormalSaveCannotInsertAnotherImageIdentity() async throws {
        let image = try importPhoto()
        let first = Conversation(title: "First", messages: [ChatMessage(role: .user, content: "Photo", attachments: [image])])
        try await store.save(first)
        var conflict = image
        conflict.mediaType = "image/png"
        conflict.relativePath = image.id.uuidString + ".png"
        let inserted = Conversation(title: "Must not insert", messages: [ChatMessage(role: .user, content: "Other format", attachments: [conflict])])
        do {
            try await store.save(inserted)
            XCTFail("Conflicting new image identity was saved")
        } catch ConversationError.unsafeAttachment { } catch { XCTFail("Unexpected error: \(error)") }
        try await assertStoreContains([first], memories: [])
        try await assertFullExportRestores()
    }

    func testNormalSaveCanReplaceItsOwnUnsharedIdentity() async throws {
        let image = try importPhoto()
        var value = Conversation(messages: [ChatMessage(role: .user, content: "Photo", attachments: [image])])
        try await store.save(value)
        value.messages[0].attachments[0].byteCount += 1
        try await store.save(value)
        try await assertStoreContains([value], memories: [])
        try await assertFullExportRestores()
        XCTAssertNil(service.previewURL(for: value.messages[0].attachments[0]))
    }

    func testPartialImportRemovingOneReferenceAllowsLaterReplacementOfLastReference() async throws {
        let image = try importPhoto()
        var first = Conversation(title: "First", messages: [ChatMessage(role: .user, content: "Photo", attachments: [image])])
        var branch = try first.branching(through: XCTUnwrap(first.messages.first?.id))
        try await store.save(first)
        try await store.save(branch)
        first.messages[0].attachments = []
        try await store.importData(JSONEncoder().encode(ConversationBackup(conversations: [first], memories: [])))
        branch.messages[0].attachments[0].byteCount += 1
        try await store.save(branch)
        try await assertStoreContains([first, branch], memories: [])
        try await assertFullExportRestores()
    }

    func testCleanupDropsUnreferencedProvenanceButKeepsSharedAssetRecord() throws {
        let retained = try importPhoto()
        let removed = try importPhoto()
        let originalBytes = try Data(contentsOf: XCTUnwrap(service.url(for: removed)))
        let previewBytes = try Data(contentsOf: XCTUnwrap(service.previewURL(for: removed)))
        try service.removeUnreferenced(keeping: retained.localRelativePaths)
        let reopened = try AttachmentService(directory: service.directory)
        XCTAssertNotNil(reopened.previewURL(for: retained))
        XCTAssertNil(reopened.previewURL(for: removed))
        // Recreate the former bytes without importing: an orphaned record must not reauthorize them.
        try originalBytes.write(to: service.directory.appendingPathComponent(removed.relativePath))
        try previewBytes.write(to: service.directory.appendingPathComponent(XCTUnwrap(removed.previewRelativePath)))
        XCTAssertNil(reopened.previewURL(for: removed))
        try assertSanitizedBoundedJPEG(XCTUnwrap(reopened.previewURL(for: retained)))
    }

    func testDirectRemovalAndRemoveAllAlsoRemovePrivateProvenance() throws {
        for removeAll in [false, true] {
            let image = try importPhoto()
            let originalBytes = try Data(contentsOf: XCTUnwrap(service.url(for: image)))
            let previewBytes = try Data(contentsOf: XCTUnwrap(service.previewURL(for: image)))
            if removeAll { try service.removeAll() } else { service.remove(image) }
            try originalBytes.write(to: service.directory.appendingPathComponent(image.relativePath))
            try previewBytes.write(to: service.directory.appendingPathComponent(XCTUnwrap(image.previewRelativePath)))
            XCTAssertNil(service.previewURL(for: image))
            XCTAssertNil(service.url(for: image))
        }
    }

    private func importPhoto() throws -> ChatAttachment {
        try service.importImage(data: photoBytes(), suggestedName: "GPS-bearing-original.jpg")
    }

    private func provenanceDirectory() -> URL {
        service.directory.deletingLastPathComponent().appendingPathComponent(service.directory.lastPathComponent + ".image-provenance")
    }

    private func photoBytes() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        let metadata: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.123,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.456,
                kCGImagePropertyGPSLongitudeRef: "W"
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05"]
        ]
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    private func saveAndExport(_ images: [ChatAttachment]) async throws -> ConversationBackup {
        let value = Conversation(messages: [ChatMessage(role: .user, content: "Photos", attachments: images)])
        try await store.save(value)
        let data = try await store.exportData()
        return try JSONDecoder().decode(ConversationBackup.self, from: data)
    }

    private func assertRejectedBackup(_ original: ConversationBackup, replacingFirstWith image: ChatAttachment) async throws {
        var backup = original
        backup.conversations[0].messages[0].attachments[0] = image
        backup.memories = [MemoryNote(content: "Must not merge")]
        try await assertRejected(backup)
        let saved = try await store.load(id: original.conversations[0].id)
        let notes = try await store.memories()
        XCTAssertEqual(saved, original.conversations[0])
        XCTAssertTrue(notes.isEmpty)
    }

    private func assertRejected(_ backup: ConversationBackup) async throws {
        do {
            try await store.importData(JSONEncoder().encode(backup))
            XCTFail("Untrusted image binding was accepted")
        } catch ConversationError.unsafeAttachment { } catch { XCTFail("Unexpected error: \(error)") }
    }

    private func assertStoreContains(_ conversations: [Conversation], memories: [MemoryNote]) async throws {
        let saved = try await store.list(includeArchived: true)
        let notes = try await store.memories()
        XCTAssertEqual(saved.sorted { $0.id.uuidString < $1.id.uuidString }, conversations.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(notes.sorted { $0.id.uuidString < $1.id.uuidString }, memories.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    private func assertFullExportRestores() async throws {
        let data = try await store.exportData()
        let restored = try SQLiteConversationStore(url: root.appendingPathComponent(UUID().uuidString + ".sqlite"))
        try await restored.importData(data)
        let originalValues = try await store.list(includeArchived: true)
        let originalNotes = try await store.memories()
        let restoredValues = try await restored.list(includeArchived: true)
        let restoredNotes = try await restored.memories()
        XCTAssertEqual(restoredValues.sorted { $0.id.uuidString < $1.id.uuidString }, originalValues.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(restoredNotes.sorted { $0.id.uuidString < $1.id.uuidString }, originalNotes.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    private func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func assertSanitizedBoundedJPEG(_ url: URL) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
        let values = try properties(url)
        XCTAssertNil(values[kCGImagePropertyGPSDictionary])
        XCTAssertNil((values[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertLessThanOrEqual(try XCTUnwrap(values[kCGImagePropertyPixelWidth] as? NSNumber).intValue, 2048)
        XCTAssertLessThanOrEqual(try XCTUnwrap(values[kCGImagePropertyPixelHeight] as? NSNumber).intValue, 2048)
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(pixels.width, 2048)
        XCTAssertLessThanOrEqual(pixels.height, 2048)
    }
}
