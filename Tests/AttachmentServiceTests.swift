import XCTest
import PDFKit
import UIKit
@testable import JarvisEVO

@MainActor
final class AttachmentServiceTests: XCTestCase {
    private var root: URL!
    private var service: AttachmentService!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        service = try AttachmentService(directory: root.appendingPathComponent("Attachments", isDirectory: true))
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    // A source-path reference instead of a private copy loses files after picker access ends.
    func testUTF8ImportCopiesBytesAndExtractsUnicodeText() throws {
        let bytes = Data("A café, 日本語, and 🦉.\nSecond line.".utf8)
        let source = try write(bytes, named: "notes.txt")
        let attachment = try service.importFile(at: source)
        let stored = try XCTUnwrap(service.url(for: attachment))
        XCTAssertNotEqual(stored, source)
        XCTAssertEqual(stored.deletingLastPathComponent(), service.directory)
        XCTAssertEqual(attachment.name, "notes.txt")
        XCTAssertEqual(attachment.mediaType, "text/plain")
        XCTAssertEqual(attachment.extractedText, "A café, 日本語, and 🦉.\nSecond line.")
        XCTAssertEqual(attachment.byteCount, bytes.count)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: stored), bytes)
    }

    func testJSONImportPreservesContentForAnalysis() throws {
        let source = try write(Data(#"{"quantity":4,"label":"kiwi"}"#.utf8), named: "data.json")
        let attachment = try service.importFile(at: source)
        XCTAssertEqual(attachment.extractedText, #"{"quantity":4,"label":"kiwi"}"#)
        XCTAssertNotNil(service.url(for: attachment))
    }

    // Reusing the original filename would overwrite an earlier attachment of the same name.
    func testRepeatedImportGetsIndependentCopies() throws {
        let source = try write(Data("first".utf8), named: "same.txt")
        let first = try service.importFile(at: source)
        try Data("second".utf8).write(to: source)
        let second = try service.importFile(at: source)
        XCTAssertNotEqual(first.relativePath, second.relativePath)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(service.url(for: first)), encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(service.url(for: second)), encoding: .utf8), "second")
    }

    func testPDFExtractsSelectableTextFromMultiplePages() throws {
        let source = try write(pdf(pages: ["Page one: 17 apples", "Page two: 23 pears"]), named: "report.pdf")
        let attachment = try service.importFile(at: source)
        XCTAssertEqual(attachment.mediaType, "application/pdf")
        XCTAssertTrue(attachment.extractedText?.contains("Page one: 17 apples") == true)
        XCTAssertTrue(attachment.extractedText?.contains("Page two: 23 pears") == true)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(service.url(for: attachment))), try Data(contentsOf: source))
    }

    func testEncryptedPDFIsRejectedWithoutLeavingCopy() throws {
        let document = try XCTUnwrap(PDFDocument(data: pdf(pages: ["Private PDF"])))
        let locked = try XCTUnwrap(document.dataRepresentation(options: [PDFDocumentWriteOption.ownerPasswordOption: "owner-test-only", PDFDocumentWriteOption.userPasswordOption: "reader-test-only"]))
        XCTAssertTrue(try XCTUnwrap(PDFDocument(data: locked)).isLocked, "The fixture must actually require a password")
        let source = try write(locked, named: "encrypted.pdf")
        assertRejected(source, as: .unreadablePDF)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testMalformedPDFIsRejectedWithoutLeavingCopy() throws {
        let source = try write(Data("%PDF-1.7\nThis is not a PDF document.".utf8), named: "broken.pdf")
        assertRejected(source, as: .unreadablePDF)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testPDFWithoutSelectableTextIsRejectedWithoutLeavingCopy() throws {
        let source = try write(pdf(pages: [""]), named: "blank.pdf")
        assertRejected(source, as: .noExtractableText)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testNonUTF8TextIsRejectedWithoutLeavingCopy() throws {
        let source = try write(Data([0xFF, 0xFE, 0x00, 0xD8]), named: "invalid.txt")
        assertRejected(source, as: .notUTF8)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testEmptyAndOversizedFilesAreRejectedBeforeCopying() throws {
        assertRejected(try write(Data(), named: "empty.txt"), as: .invalidSize)
        assertRejected(try write(Data(repeating: 0x61, count: 10 * 1024 * 1024 + 1), named: "too-large.txt"), as: .invalidSize)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testUnsupportedBinaryIsRejectedBeforeCopying() throws {
        assertRejected(try write(Data([0x50, 0x4B, 0x03, 0x04]), named: "archive.zip"), as: .unsupportedType)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    // Truncation must be in Swift characters, not broken UTF-8 bytes or a silent omission.
    func testLongUnicodeTextHasExplicitExtractionLimitButKeepsOriginalBytes() throws {
        let text = String(repeating: "🦉", count: 60_001)
        let source = try write(Data(text.utf8), named: "long.txt")
        let attachment = try service.importFile(at: source)
        XCTAssertEqual(attachment.extractedText, String(repeating: "🦉", count: 60_000) + "\n[Attachment truncated at 60,000 characters.]")
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(service.url(for: attachment)), encoding: .utf8), text)
    }

    func testImportedMetadataCannotTraverseOutsideAttachmentDirectory() throws {
        let external = try write(Data("private".utf8), named: "secret.txt")
        for path in ["../secret.txt", "../../secret.txt", external.path, "sub/../../secret.txt", "..\\secret.txt", "", "."] {
            XCTAssertNil(service.url(for: metadata(path)), "Unsafe path: \(path)")
        }
        XCTAssertEqual(try String(contentsOf: external, encoding: .utf8), "private")
    }

    // An existing symlink is not a safe attachment merely because its name has no traversal.
    func testAttachmentLookupRejectsSymlinkToFileOutsideDirectory() throws {
        let external = try write(Data("private outside attachment storage".utf8), named: "secret.txt")
        let link = service.directory.appendingPathComponent("linked.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        XCTAssertNil(service.url(for: metadata("linked.txt")))
    }

    func testAttachmentLookupRejectsBrokenSymlink() throws {
        let link = service.directory.appendingPathComponent("missing.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("does-not-exist.txt"))
        XCTAssertNil(service.url(for: metadata("missing.txt")))
    }

    func testAttachmentLookupRejectsSymlinkEvenWhenTargetIsInsideDirectory() throws {
        let source = try write(Data("real attachment".utf8), named: "safe.txt")
        let attachment = try service.importFile(at: source)
        let stored = try XCTUnwrap(service.url(for: attachment))
        try FileManager.default.createSymbolicLink(at: service.directory.appendingPathComponent("alias.txt"), withDestinationURL: stored)
        XCTAssertNil(service.url(for: metadata("alias.txt")))
        XCTAssertNotNil(service.url(for: attachment))
    }

    func testAttachmentLookupRejectsDirectoryInsteadOfFile() throws {
        try FileManager.default.createDirectory(at: service.directory.appendingPathComponent("folder.txt"), withIntermediateDirectories: true)
        XCTAssertNil(service.url(for: metadata("folder.txt")))
    }

    func testCleanupKeepsReferencedFilesAndRemovesOnlyUnreferencedCopies() throws {
        let source = try write(Data("retained".utf8), named: "source.txt")
        let first = try service.importFile(at: source)
        let second = try service.importFile(at: source)
        try service.removeUnreferenced(keeping: [first.relativePath])
        XCTAssertNotNil(service.url(for: first))
        XCTAssertNil(service.url(for: second))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        service.remove(first)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    private func write(_ data: Data, named name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
    private func storedFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: service.directory, includingPropertiesForKeys: nil)
    }
    private func metadata(_ path: String) -> ChatAttachment {
        ChatAttachment(name: "Imported", relativePath: path, mediaType: "text/plain", byteCount: 1)
    }
    private func assertRejected(_ url: URL, as expected: AttachmentError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try service.importFile(at: url), file: file, line: line) { error in
            XCTAssertTrue(error is AttachmentError, "Unexpected error: \(error)", file: file, line: line)
            XCTAssertEqual((error as? AttachmentError)?.errorDescription, expected.errorDescription, file: file, line: line)
        }
    }
    private func pdf(pages: [String]) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 300)).pdfData { context in
            for text in pages {
                context.beginPage()
                (text as NSString).draw(at: CGPoint(x: 20, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
    }
}

@MainActor
final class AttachmentAppFlowTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "JarvisEVO.AttachmentAppFlowTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func testFourAttachmentLimitRejectsExtraFileWithoutDiscardingExistingFiles() async throws {
        let (model, _) = try fixture("limits")
        let source = try textFile("notes.txt", content: "Four copies")
        await model.addAttachments(from: [source, source, source, source])
        XCTAssertEqual(model.pendingAttachments.count, 4)
        await model.addAttachments(from: [source])
        XCTAssertEqual(model.pendingAttachments.count, 4)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: model.attachmentService.directory.path).count, 4)
    }

    func testRemovingPendingAttachmentDeletesItsCopyAndDisablesEmptySend() async throws {
        let (model, _) = try fixture("remove")
        await model.addAttachments(from: [try textFile("notes.txt", content: "Pending attachment")])
        let attachment = try XCTUnwrap(model.pendingAttachments.first)
        XCTAssertTrue(model.canSend)
        model.removePendingAttachment(attachment)
        XCTAssertFalse(model.canSend)
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertNil(model.attachmentService.url(for: attachment))
    }

    func testInvalidAttachmentReportsErrorAndPreservesExistingDraftAndAttachment() async throws {
        let (model, _) = try fixture("invalid")
        model.draft = "Keep this question"
        await model.addAttachments(from: [try textFile("good.txt", content: "Valid document")])
        await model.addAttachments(from: [try textFile("bad.pdf", content: "Not a PDF")])
        XCTAssertEqual(model.draft, "Keep this question")
        XCTAssertEqual(model.pendingAttachments.count, 1)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: model.attachmentService.directory.path).count, 1)
    }

    // Backup intentionally transfers extracted text, not source file bytes or arbitrary file access.
    func testAppBackupRestoresExtractedAttachmentTextAndMemoryWithoutInventingOriginalFile() async throws {
        let (first, firstStore) = try fixture("first")
        let attachment = try first.attachmentService.importFile(at: textFile("analysis.txt", content: "Revenue was 42 units."))
        let conversation = Conversation(title: "Analysis", messages: [ChatMessage(role: .user, content: "Summarize", attachments: [attachment])])
        try await firstStore.save(conversation)
        await first.saveMemory(content: "Use metric units")
        let backup = try await first.exportData()
        let backupURL = root.appendingPathComponent("backup.json")
        try backup.write(to: backupURL)
        let (second, secondStore) = try fixture("second")
        await second.importHistory(from: backupURL)
        XCTAssertNil(second.errorMessage)
        let storedConversation = try await secondStore.load(id: conversation.id)
        let restored = try XCTUnwrap(storedConversation)
        XCTAssertEqual(restored.messages.first?.attachments.first?.extractedText, "Revenue was 42 units.")
        XCTAssertTrue(restored.messages[0].promptContent.contains("Revenue was 42 units."))
        XCTAssertEqual(second.memories.map(\.content), ["Use metric units"])
        XCTAssertNil(second.attachmentService.url(for: attachment))
        let secondExport = try await second.exportData()
        let roundTrip = try JSONDecoder().decode(ConversationBackup.self, from: secondExport)
        XCTAssertEqual(roundTrip.conversations.first?.id, conversation.id)
    }

    func testMixedUnsafeBackupDoesNotPartiallyMergeConversationOrMemory() async throws {
        let (model, store) = try fixture("transaction")
        let existing = Conversation(title: "Keep existing")
        try await store.save(existing)
        await model.bootstrap()
        let safe = Conversation(title: "Must not be added")
        let unsafe = ChatAttachment(name: "secret", relativePath: "../secret.txt", mediaType: "text/plain", byteCount: 1)
        let invalid = Conversation(messages: [ChatMessage(role: .user, content: "Unsafe", attachments: [unsafe])])
        let backup = ConversationBackup(conversations: [safe, invalid], memories: [MemoryNote(content: "Must not be added")])
        let url = root.appendingPathComponent("unsafe.json")
        try JSONEncoder().encode(backup).write(to: url)
        await model.importHistory(from: url)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.conversations.map(\.id), [existing.id])
        let stored = try await store.list(includeArchived: true)
        let memory = try await store.memories()
        XCTAssertEqual(stored.map(\.id), [existing.id])
        XCTAssertTrue(memory.isEmpty)
    }

    private func textFile(_ name: String, content: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(content.utf8).write(to: url)
        return url
    }
    private func fixture(_ name: String) throws -> (AppModel, SQLiteConversationStore) {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try SQLiteConversationStore(url: directory.appendingPathComponent("test.sqlite"))
        let attachments = try AttachmentService(directory: directory.appendingPathComponent("Attachments"))
        let models = try LocalModelStore(root: directory.appendingPathComponent("Models"))
        return (AppModel(store: store, attachmentService: attachments, modelStore: models, defaults: defaults), store)
    }
}

final class AttachmentAnalysisIntegrationTests: XCTestCase {
    /// Genuine local inference on an imported file. This is a narrow fact-retrieval
    /// fixture, not a quality benchmark or proof of physical-device offline behavior.
    func testRealLocalModelAnswersFromImportedTextAttachment() async throws {
        let configured = ProcessInfo.processInfo.environment["JARVIS_TEST_GGUF"]
        let bundled = Bundle(for: AttachmentAnalysisIntegrationTests.self).url(forResource: "qwen2.5-0.5b-instruct-q4_k_m", withExtension: "gguf")?.path
        guard let modelPath = configured.flatMap({ $0.isEmpty ? nil : $0 }) ?? bundled else {
            if ProcessInfo.processInfo.environment["JARVIS_REQUIRE_REAL_INFERENCE"] == "1" {
                XCTFail("Attachment analysis requires the real GGUF fixture, but it is missing.")
                return
            }
            throw XCTSkip("Real GGUF weights are required for file-analysis integration.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let attachments = try AttachmentService(directory: root.appendingPathComponent("Attachments"))
        let source = root.appendingPathComponent("orchard.txt")
        try Data("The orchard sold 42 apples on Tuesday. It sold 17 pears on Wednesday.".utf8).write(to: source)
        let attachment = try attachments.importFile(at: source)
        let store = try LocalModelStore(root: root.appendingPathComponent("Models"))
        let descriptor = try await store.importModel(from: URL(fileURLWithPath: modelPath))
        let provider = LocalAIProvider(store: store, model: descriptor)
        let request = GenerationRequest(
            messages: [ChatMessage(role: .user, content: "According to the attached document, how many apples were sold on Tuesday? Answer with only the number.", attachments: [attachment])],
            systemPrompt: "Answer the user's question using the attached document.", maxTokens: 32, temperature: 0
        )
        var answer = ""
        do {
            for try await piece in try await provider.stream(request) { answer += piece }
        } catch {
            await provider.unload()
            throw error
        }
        await provider.unload()
        XCTAssertNotNil(answer.range(of: #"\b42\b"#, options: .regularExpression), "The real model did not retrieve the fixture's apple count. Response: \(answer)")
    }
}
