import XCTest
import UIKit
@testable import JarvisEVO

final class ImageAttachmentMetadataTests: XCTestCase {
    func testLegacyAttachmentWithoutPreviewStillDecodesAndRoundTrips() throws {
        let json = Data(#"{"id":"E5769B36-F1F4-44D4-BBE2-EA7489B2A793","name":"old.txt","relativePath":"old.txt","mediaType":"text/plain","byteCount":5,"extractedText":"Hello"}"#.utf8)
        let old = try JSONDecoder().decode(ChatAttachment.self, from: json)
        XCTAssertNil(old.previewRelativePath)
        XCTAssertFalse(old.isImage)
        XCTAssertEqual(old.localRelativePaths, ["old.txt"])
        XCTAssertEqual(try JSONDecoder().decode(ChatAttachment.self, from: JSONEncoder().encode(old)), old)
    }

    func testImageMetadataRoundTripKeepsPreviewAndOCRContextWithoutEmbeddingBytes() throws {
        let id = UUID()
        let value = ChatAttachment(id: id, name: "Receipt", relativePath: id.uuidString + ".png", mediaType: "image/png", byteCount: 123,
                                   extractedText: "On-device OCR: 42 apples", previewRelativePath: id.uuidString + "-preview.jpg")
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(ChatAttachment.self, from: data), value)
        XCTAssertEqual(value.localRelativePaths, [id.uuidString + ".png", id.uuidString + "-preview.jpg"])
        XCTAssertTrue(value.isImage)
        let message = ChatMessage(role: .user, content: "Read this", attachments: [value])
        XCTAssertTrue(message.promptContent.contains("image"))
        XCTAssertTrue(message.promptContent.contains("has not received image pixels"))
        XCTAssertTrue(message.promptContent.contains("42 apples"))
    }

    // Invalid preview metadata must be caught before any conversation or memory merge starts.
    func testUnsafePreviewBackupIsRejectedAtomically() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("test.sqlite"))
        let existing = Conversation(title: "Keep original")
        try await store.save(existing)
        for path in ["../secret.jpg", "/private/secret.jpg", "folder/preview.jpg", "..\\secret.jpg", ".", "", "a\u{0}b.jpg"] {
            var replacement = existing
            replacement.title = "Must not replace"
            let imageID = UUID()
            let image = ChatAttachment(id: imageID, name: "Photo", relativePath: imageID.uuidString + ".png", mediaType: "image/png", byteCount: 10,
                                       previewRelativePath: path)
            let unsafe = Conversation(messages: [ChatMessage(role: .user, content: "Photo", attachments: [image])])
            let bytes = try JSONEncoder().encode(ConversationBackup(conversations: [replacement, unsafe], memories: [MemoryNote(content: "Must not merge")]))
            do {
                try await store.importData(bytes)
                XCTFail("Unsafe preview accepted: \(path)")
            } catch ConversationError.unsafeAttachment { } catch { XCTFail("Unexpected error: \(error)") }
            let saved = try await store.list(includeArchived: true)
            let notes = try await store.memories()
            XCTAssertEqual(saved, [existing])
            XCTAssertTrue(notes.isEmpty)
        }
    }
}

@MainActor
final class ImageAttachmentAppFlowTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "JarvisEVO.ImageAttachmentAppFlowTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func testImageBytesBecomePendingOCRAttachmentAndRemovalDeletesBothFiles() async throws {
        let (model, _) = try fixture()
        await model.addImageAttachment(data: png(), suggestedName: "Photo.png")
        let value = try XCTUnwrap(model.pendingAttachments.first)
        XCTAssertTrue(value.isImage)
        XCTAssertNotNil(model.attachmentService.url(for: value))
        XCTAssertNotNil(model.attachmentService.previewURL(for: value))
        XCTAssertTrue(value.extractedText?.contains("has not received image pixels") == true)
        XCTAssertTrue(model.canSend)
        XCTAssertFalse(model.isImportingAttachments)
        XCTAssertEqual(try files(model).count, 2)
        model.removePendingAttachment(value)
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertFalse(model.canSend)
        XCTAssertTrue(try files(model).isEmpty)
    }

    func testFilesImporterRoutesRealPNGThroughImagePipeline() async throws {
        let (model, _) = try fixture()
        let source = root.appendingPathComponent("file.png")
        try png().write(to: source)
        await model.addAttachments(from: [source])
        let value = try XCTUnwrap(model.pendingAttachments.first)
        XCTAssertEqual(value.mediaType, "image/png")
        XCTAssertNotNil(model.attachmentService.previewURL(for: value))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(model.attachmentService.url(for: value))), try Data(contentsOf: source))
    }

    func testPreviewLookupRejectsSymlinkEvenToAnotherFileInStorage() throws {
        let (model, _) = try fixture()
        var image = try model.attachmentService.importImage(data: png(), suggestedName: "safe.png")
        let actualPreview = try XCTUnwrap(model.attachmentService.previewURL(for: image))
        let alias = model.attachmentService.directory.appendingPathComponent("alias.jpg")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actualPreview)
        image.previewRelativePath = "alias.jpg"
        XCTAssertNil(model.attachmentService.previewURL(for: image))
        image.previewRelativePath = "../outside.jpg"
        XCTAssertNil(model.attachmentService.previewURL(for: image))
        XCTAssertTrue(FileManager.default.fileExists(atPath: actualPreview.path))
    }

    func testStalePickerTransferIsIgnoredBeforeCreatingAnyFiles() async throws {
        let (model, _) = try fixture()
        let pickerContext = model.attachmentImportContext
        await model.newConversation()
        model.draft = "The new chat"
        await model.addImageAttachment(data: png(), suggestedName: "old-selection.png", context: pickerContext)
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertEqual(model.draft, "The new chat")
        XCTAssertFalse(model.isImportingAttachments)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(try files(model).isEmpty)
    }

    func testSendingDraftInvalidatesPhotoTransferForThatDraft() async throws {
        let (model, _) = try fixture()
        model.replaceProviders([ProviderOption(id: "immediate", title: "Test", detail: "Test only", provider: ImageFlowTextProvider())])
        let pickerContext = model.attachmentImportContext
        model.draft = "Send this text"
        model.send()
        await model.addImageAttachment(data: png(), suggestedName: "late-selection.png", context: pickerContext)
        try await waitFor { !model.isGenerating }
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertTrue(model.activeConversation?.messages.first?.attachments.isEmpty == true)
        XCTAssertTrue(try files(model).isEmpty)
    }

    // Real store validation rejects this turn. Reserving another batch before that save settles
    // would allow restored attachments plus late arrivals to exceed the four-file composer limit.
    func testInitialSaveFailureBlocksNewImportsAndRestoresFourImages() async throws {
        let (model, _) = try fixture()
        model.replaceProviders([ProviderOption(id: "immediate", title: "Test", detail: "Test only", provider: ImageFlowTextProvider())])
        for index in 0..<4 { model.pendingAttachments.append(try model.attachmentService.importImage(data: png(), suggestedName: "\(index).png")) }
        let originals = model.pendingAttachments
        model.draft = String(repeating: "x", count: 1_000_001)
        model.send()
        XCTAssertEqual(model.availableAttachmentSlots, 0)
        await model.addImageAttachment(data: png(), suggestedName: "must-not-start.png")
        try await waitFor { !model.isGenerating }
        XCTAssertEqual(model.pendingAttachments, originals)
        XCTAssertEqual(model.draft.count, 1_000_001)
        XCTAssertEqual(try files(model).count, 8)
        XCTAssertNotNil(model.errorMessage)
    }

    func testInitialSaveFailureAfterSwitchDoesNotOverwriteOtherComposer() async throws {
        let (model, store) = try fixture()
        let other = Conversation(title: "Other chat")
        try await store.save(other)
        await model.bootstrap()
        model.selectedConversationID = nil
        model.replaceProviders([ProviderOption(id: "immediate", title: "Test", detail: "Test only", provider: ImageFlowTextProvider())])
        let image = try model.attachmentService.importImage(data: png(), suggestedName: "failed-send.png")
        model.pendingAttachments = [image]
        model.draft = String(repeating: "x", count: 1_000_001)
        model.send()
        let originalID = try XCTUnwrap(model.selectedConversationID)
        model.selectConversation(other.id)
        model.draft = "Keep the other chat's draft"
        try await waitFor { !model.isGenerating }
        XCTAssertEqual(model.selectedConversationID, other.id)
        XCTAssertEqual(model.draft, "Keep the other chat's draft")
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        let unsaved = try XCTUnwrap(model.conversations.first { $0.id == originalID })
        XCTAssertEqual(unsaved.messages.first?.attachments, [image])
        XCTAssertEqual(unsaved.messages.last?.state, .failed)
        XCTAssertNotNil(model.attachmentService.url(for: image))
        XCTAssertNotNil(model.attachmentService.previewURL(for: image))
        XCTAssertNotNil(model.statusMessage)
    }

    func testMultipleImagesKeepIndependentPreviewsAndClearRemovesAllCopies() async throws {
        let (model, _) = try fixture()
        await model.addImageAttachment(data: png(), suggestedName: "One.png")
        await model.addImageAttachment(data: png(), suggestedName: "Two.png")
        XCTAssertEqual(model.pendingAttachments.count, 2)
        XCTAssertEqual(Set(model.pendingAttachments.compactMap(\.previewRelativePath)).count, 2)
        XCTAssertEqual(try files(model).count, 4)
        model.clearPendingAttachments()
        XCTAssertTrue(try files(model).isEmpty)
    }

    func testDeletingBranchesRetainsOriginalAndPreviewUntilFinalReference() async throws {
        let (model, store) = try fixture()
        let image = try model.attachmentService.importImage(data: png(), suggestedName: "shared.png")
        let message = ChatMessage(role: .user, content: "Read", attachments: [image])
        let original = Conversation(messages: [message])
        try await store.save(original)
        await model.bootstrap()
        model.selectConversation(original.id)
        let branched = await model.branch(through: message.id)
        XCTAssertTrue(branched)
        let branchID = try XCTUnwrap(model.selectedConversationID)
        await model.delete(original.id)
        XCTAssertNotNil(model.attachmentService.url(for: image))
        XCTAssertNotNil(model.attachmentService.previewURL(for: image))
        await model.delete(branchID)
        XCTAssertTrue(try files(model).isEmpty)
    }

    func testRemovingPendingReferenceDoesNotDeleteFilesUsedBySavedConversation() async throws {
        let (model, store) = try fixture()
        let image = try model.attachmentService.importImage(data: png(), suggestedName: "shared.png")
        let saved = Conversation(messages: [ChatMessage(role: .user, content: "Keep", attachments: [image])])
        try await store.save(saved)
        await model.bootstrap()
        model.pendingAttachments = [image]
        model.removePendingAttachment(image)
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertNotNil(model.attachmentService.url(for: image))
        XCTAssertNotNil(model.attachmentService.previewURL(for: image))
    }

    func testHistoryMergeRemovesSupersededOriginalAndPreview() async throws {
        let (model, store) = try fixture()
        let image = try model.attachmentService.importImage(data: png(), suggestedName: "old.png")
        var saved = Conversation(messages: [ChatMessage(role: .user, content: "Old", attachments: [image])])
        try await store.save(saved)
        await model.bootstrap()
        saved.messages = [ChatMessage(role: .user, content: "Replacement without image")]
        let backup = root.appendingPathComponent("replacement.json")
        try JSONEncoder().encode(ConversationBackup(conversations: [saved], memories: [])).write(to: backup)
        await model.importHistory(from: backup, policy: .replaceMatching)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.conversations.first?.messages.first?.content, "Replacement without image")
        XCTAssertTrue(try files(model).isEmpty)
    }


    func testDefaultHistoryMergePreservesLocalOriginalAndPreview() async throws {
        let (model, store) = try fixture()
        let image = try model.attachmentService.importImage(data: png(), suggestedName: "keep.png")
        let saved = Conversation(messages: [ChatMessage(role: .user, content: "Keep local", attachments: [image])])
        try await store.save(saved)
        await model.bootstrap()
        let before = try files(model)
        var replacement = saved
        replacement.messages = [ChatMessage(role: .user, content: "Backup without image")]
        let backup = root.appendingPathComponent("preserve.json")
        try JSONEncoder().encode(ConversationBackup(conversations: [replacement], memories: [])).write(to: backup)
        await model.importHistory(from: backup)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.conversations.first?.messages, saved.messages)
        XCTAssertNotNil(model.attachmentService.url(for: image))
        XCTAssertNotNil(model.attachmentService.previewURL(for: image))
        XCTAssertEqual(Set(try files(model)), Set(before))
    }

    func testRestoredImageMetadataKeepsOCRButDoesNotInventMissingImageFiles() async throws {
        let (model, _) = try fixture()
        let id = UUID()
        let image = ChatAttachment(id: id, name: "Receipt", relativePath: id.uuidString + ".png", mediaType: "image/png", byteCount: 123,
                                   extractedText: "OCR: 42 apples", previewRelativePath: id.uuidString + "-preview.jpg")
        let saved = Conversation(messages: [ChatMessage(role: .user, content: "Read", attachments: [image])])
        let backup = root.appendingPathComponent("restored.json")
        try JSONEncoder().encode(ConversationBackup(conversations: [saved], memories: [])).write(to: backup)
        await model.importHistory(from: backup)
        XCTAssertNil(model.errorMessage)
        let restored = try XCTUnwrap(model.conversations.first?.messages.first?.attachments.first)
        XCTAssertEqual(restored, image)
        XCTAssertNil(model.attachmentService.url(for: restored))
        XCTAssertNil(model.attachmentService.previewURL(for: restored))
        XCTAssertTrue(model.conversations[0].messages[0].promptContent.contains("42 apples"))
    }

    // The controlled boundary delays delivery, not processing: actual image files already exist here.
    func testSwitchingChatRejectsLateImageAndPreservesNewDraft() async throws {
        let (model, store, held) = try gatedFixture()
        let first = Conversation(title: "First")
        let second = Conversation(title: "Second")
        try await store.save(first)
        try await store.save(second)
        await model.bootstrap()
        model.selectConversation(first.id)
        let bytes = png()
        let importing = Task { await model.addImageAttachment(data: bytes, suggestedName: "late.png") }
        try await waitFor { await held.isHolding }
        XCTAssertTrue(model.isImportingAttachments)
        XCTAssertFalse(model.canSend)
        XCTAssertEqual(try files(model).count, 2)
        model.selectConversation(second.id)
        model.draft = "Keep this new draft"
        await held.release()
        await importing.value
        XCTAssertEqual(model.selectedConversationID, second.id)
        XCTAssertEqual(model.draft, "Keep this new draft")
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertFalse(model.isImportingAttachments)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(try files(model).isEmpty)
    }

    func testNewConversationInvalidatesInFlightImageBeforeCompletion() async throws {
        let (model, _, held) = try gatedFixture()
        let bytes = png()
        let importing = Task { await model.addImageAttachment(data: bytes, suggestedName: "late.png") }
        try await waitFor { await held.isHolding }
        await model.newConversation()
        await held.release()
        await importing.value
        XCTAssertNotNil(model.selectedConversationID)
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertTrue(try files(model).isEmpty)
    }

    func testConcurrentImportReservationsEnforceFourAttachmentLimit() async throws {
        let (model, _, held) = try gatedFixture()
        let source = root.appendingPathComponent("four.png")
        try png().write(to: source)
        let importing = Task { await model.addAttachments(from: [source, source, source, source]) }
        try await waitFor { await held.isHolding }
        XCTAssertEqual(model.availableAttachmentSlots, 0)
        await model.addImageAttachment(data: png(), suggestedName: "fifth.png")
        XCTAssertNotNil(model.errorMessage)
        await held.release()
        await importing.value
        XCTAssertEqual(model.pendingAttachments.count, 4)
        XCTAssertEqual(try files(model).count, 8)
    }

    func testCallerCancellationCleansAlreadyImportedFilesAndDoesNotShowError() async throws {
        let (model, _, held) = try gatedFixture()
        let bytes = png()
        let importing = Task { await model.addImageAttachment(data: bytes, suggestedName: "cancel.png") }
        try await waitFor { await held.isHolding }
        importing.cancel()
        await held.release()
        await importing.value
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isImportingAttachments)
        XCTAssertTrue(try files(model).isEmpty)
    }

    func testDeleteAllWaitsForLateImportCleanupWithoutResurrectingFiles() async throws {
        let (model, _, held) = try gatedFixture()
        let bytes = png()
        let importing = Task { await model.addImageAttachment(data: bytes, suggestedName: "late.png") }
        try await waitFor { await held.isHolding }
        await model.deleteAllContent()
        await held.release()
        await importing.value
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertTrue(try files(model).isEmpty)
    }

    func testCleanupDuringImportDoesNotDeleteItsUnregisteredFiles() async throws {
        let (model, store, held) = try gatedFixture()
        let old = Conversation(title: "Delete unrelated chat")
        try await store.save(old)
        await model.bootstrap()
        model.selectedConversationID = nil
        let bytes = png()
        let importing = Task { await model.addImageAttachment(data: bytes, suggestedName: "keep.png") }
        try await waitFor { await held.isHolding }
        await model.delete(old.id)
        XCTAssertEqual(try files(model).count, 2)
        await held.release()
        await importing.value
        let image = try XCTUnwrap(model.pendingAttachments.first)
        XCTAssertNotNil(model.attachmentService.url(for: image))
        XCTAssertNotNil(model.attachmentService.previewURL(for: image))
    }

    private func fixture(importer: (any AttachmentImporting)? = nil) throws -> (AppModel, SQLiteConversationStore) {
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("test.sqlite"))
        let attachments = try AttachmentService(directory: root.appendingPathComponent("Attachments"))
        let models = try LocalModelStore(root: root.appendingPathComponent("Models"))
        let model = AppModel(offlineAutoSelection: false, store: store, attachmentService: attachments, modelStore: models, defaults: defaults, attachmentImporter: importer)
        return (model, store)
    }

    private func gatedFixture() throws -> (AppModel, SQLiteConversationStore, HoldingImageImporter) {
        let attachments = try AttachmentService(directory: root.appendingPathComponent("Attachments"))
        let held = HoldingImageImporter(service: attachments)
        let (model, store) = try fixture(importer: held)
        return (model, store, held)
    }

    private func png() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180), format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        }
    }

    private func files(_ model: AppModel) throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: model.attachmentService.directory.path) }

    private func waitFor(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { XCTFail("Timed out waiting for import boundary"); throw ImageFlowWaitError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private enum ImageFlowWaitError: Error { case timeout }

private struct ImageFlowTextProvider: AIProvider {
    let id = "immediate"
    let displayName = "Test only"
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.yield("Text response"); $0.finish() }
    }
}

/// Controls only delivery timing; every success comes from the real local importer and filesystem.
private actor HoldingImageImporter: AttachmentImporting {
    private let importer: LocalAttachmentImporter
    private var shouldHold = true
    private var continuation: CheckedContinuation<Void, Never>?
    var isHolding: Bool { continuation != nil }
    init(service: AttachmentService) { importer = LocalAttachmentImporter(service: service) }
    func importAttachment(_ source: AttachmentImportSource) async throws -> ChatAttachment {
        let result = try await importer.importAttachment(source)
        if shouldHold {
            shouldHold = false
            await withCheckedContinuation { continuation = $0 }
        }
        return result
    }
    func release() { continuation?.resume(); continuation = nil }
}
