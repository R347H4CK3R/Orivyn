import XCTest
@testable import JarvisEVO

@MainActor
final class AppModelTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "JarvisEVO.AppModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    // Removing the cancellation state transition would falsely mark partial output complete.
    func testStoppingPersistsPartialResponseAsInterrupted() async throws {
        let (model, store, source) = try await fixture()
        model.draft = "Question"
        model.send()
        try await waitFor { await source.hasSubscriber }
        await source.emit("Partial answer")
        try await waitFor { model.activeConversation?.messages.last?.content == "Partial answer" }
        let id = try XCTUnwrap(model.selectedConversationID)
        model.stop()
        try await waitFor { !model.isGenerating }
        let saved = try await store.load(id: id)
        XCTAssertEqual(saved?.messages.last?.content, "Partial answer")
        XCTAssertEqual(saved?.messages.last?.state, .interrupted)
    }

    // Using selectedConversationID in token delivery would attach the token to the wrong chat.
    func testSwitchingChatsDoesNotMoveStreamingResponse() async throws {
        let (model, store, source) = try await fixture()
        model.draft = "Original question"
        model.send()
        try await waitFor { await source.hasSubscriber }
        let originalID = try XCTUnwrap(model.selectedConversationID)
        await model.newConversation()
        let selectedID = try XCTUnwrap(model.selectedConversationID)
        XCTAssertNotEqual(originalID, selectedID)
        await source.emit("Answer for original")
        await source.finish()
        try await waitFor { !model.isGenerating }
        XCTAssertEqual(model.selectedConversationID, selectedID)
        XCTAssertEqual(model.activeConversation?.messages.count, 0)
        let saved = try await store.load(id: originalID)
        XCTAssertEqual(saved?.messages.last?.content, "Answer for original")
        XCTAssertEqual(saved?.messages.last?.state, .complete)
    }

    // Deleting without awaiting stream cancellation can recreate a deleted database row.
    func testDeletingStreamingConversationDoesNotResurrectIt() async throws {
        let (model, store, source) = try await fixture()
        model.draft = "Delete me"
        model.send()
        try await waitFor { await source.hasSubscriber }
        let id = try XCTUnwrap(model.selectedConversationID)
        await source.emit("Partial")
        await model.delete(id)
        await source.emit("late token")
        await source.finish()
        XCTAssertFalse(model.isGenerating)
        let deleted = try await store.load(id: id)
        XCTAssertNil(deleted)
        XCTAssertFalse(model.conversations.contains { $0.id == id })
    }

    func testDeletingOneBranchKeepsSharedAttachmentUntilLastReferenceIsDeleted() async throws {
        let (model, store, _) = try await fixture()
        let source = root.appendingPathComponent("original.txt")
        try Data("Shared attachment".utf8).write(to: source)
        let attachment = try model.attachmentService.importFile(at: source)
        let first = Conversation(title: "First", messages: [ChatMessage(role: .user, content: "Read", attachments: [attachment])])
        let second = Conversation(title: "Second", messages: first.messages)
        try await store.save(first)
        try await store.save(second)
        await model.bootstrap()
        await model.delete(first.id)
        XCTAssertNotNil(model.attachmentService.url(for: attachment))
        await model.delete(second.id)
        XCTAssertNil(model.attachmentService.url(for: attachment))
    }

    // Omitting the initial save would allow inference before the user turn is durable.
    func testUserMessageIsSavedBeforeProviderStarts() async throws {
        let (model, store, source) = try await fixture()
        model.draft = "Save before inference"
        model.send()
        try await waitFor { await source.hasSubscriber }
        let id = try XCTUnwrap(model.selectedConversationID)
        let saved = try await store.load(id: id)
        XCTAssertEqual(saved?.messages.first?.content, "Save before inference")
        // Any persisted streaming snapshot reads as interrupted, ready for restart recovery.
        XCTAssertEqual(saved?.messages.last?.state, .interrupted)
        model.stop()
        try await waitFor { !model.isGenerating }
    }

    // Missing provider must leave the draft editable, not clear it or fabricate a reply.
    func testMissingProviderPreservesDraft() async throws {
        let (model, _, _) = try await fixture()
        model.replaceProviders([])
        model.draft = "Keep my draft"
        model.send()
        XCTAssertEqual(model.draft, "Keep my draft")
        XCTAssertFalse(model.isGenerating)
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    // Clearing the database without clearing the screen or attachments leaves private data behind.
    func testDeletingAllContentClearsHistoryMemoryAndAttachments() async throws {
        let (model, store, _) = try await fixture()
        await model.newConversation()
        await model.saveMemory(content: "Test preference")
        let file = root.appendingPathComponent("Attachments/private.txt")
        try Data("private attachment".utf8).write(to: file)
        model.draft = "Unsent text"
        await model.deleteAllContent()
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertTrue(model.memories.isEmpty)
        XCTAssertEqual(model.draft, "")
        XCTAssertNil(model.selectedConversationID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let stored = try await store.list(includeArchived: true)
        let notes = try await store.memories()
        XCTAssertTrue(stored.isEmpty)
        XCTAssertTrue(notes.isEmpty)
    }

    func testSavedBehaviorReachesActualGenerationRequest() async throws {
        let (model, _, source) = try await fixture()
        var behavior = ResponseBehavior(); behavior.instructions = "Use concise explanations."; behavior.style = "Efficient"
        try model.workspace.saveBehavior(behavior)
        model.draft = "Test preferences"; model.send()
        try await waitFor { await source.hasSubscriber }
        let request = await source.lastRequest
        XCTAssertTrue(request?.systemPrompt.contains("Use concise explanations.") == true)
        XCTAssertTrue(request?.systemPrompt.contains("Style: Efficient") == true)
        XCTAssertTrue(request?.systemPrompt.contains("Do not claim to browse, run code") == true)
        model.stop(); try await waitFor { !model.isGenerating }
    }

    // Minimal GGUF storage headers verify engine ownership, not real inference.
    func testInstalledProvidersShareOneRuntimeAcrossReloads() async throws {
        let (model, _, _) = try await fixture()
        for index in 0..<2 {
            let file = root.appendingPathComponent("runtime-\(index).gguf")
            var bytes = Data([0x47,0x47,0x55,0x46,3,0,0,0] + Array(repeating: 0, count: 24)); bytes[31] = UInt8(index)
            try bytes.write(to: file); _ = try await model.modelStore.importModel(from: file)
        }
        try await model.reloadProviders()
        let local = model.providers.compactMap { $0.provider as? LocalAIProvider }
        XCTAssertEqual(local.count, 2); guard local.count == 2 else { return }
        XCTAssertTrue(local[0].engine === local[1].engine)
        let engine = local[0].engine
        try await model.reloadProviders()
        let reloaded = model.providers.compactMap { $0.provider as? LocalAIProvider }
        XCTAssertEqual(reloaded.count, 2); XCTAssertTrue(reloaded.allSatisfy { $0.engine === engine })
    }

    func testAcceptedIncomingTextKeepsAttachmentsAndDoesNotSubmit() async throws {
        let (model, _, source) = try await fixture()
        let file = root.appendingPathComponent("incoming-attachment.txt")
        try Data("Keep this attachment".utf8).write(to: file)
        let attachment = try model.attachmentService.importFile(at: file)
        model.pendingAttachments = [attachment]
        model.draft = "Existing draft"
        let selectedProviderID = model.selectedProviderID
        try model.acceptIncomingText("Shared text")
        XCTAssertEqual(model.draft, "Existing draft\n\nShared text")
        XCTAssertEqual(model.pendingAttachments, [attachment])
        XCTAssertEqual(model.selectedProviderID, selectedProviderID)
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertFalse(model.isGenerating)
        let subscribed = await source.hasSubscriber
        XCTAssertFalse(subscribed)
    }

    func testIncomingAcceptanceIsBlockedDuringGenerationAndPreservesDraft() async throws {
        let (model, _, source) = try await fixture()
        model.draft = "Generate"; model.send()
        try await waitFor { await source.hasSubscriber }
        model.draft = "Next draft"
        XCTAssertFalse(model.canAcceptIncomingText)
        XCTAssertThrowsError(try model.acceptIncomingText("Incoming"))
        XCTAssertEqual(model.draft, "Next draft")
        model.stop(); try await waitFor { !model.isGenerating }
    }

    func testInvalidIncomingAcceptanceCannotChangeExistingDraft() async throws {
        let (model, _, _) = try await fixture()
        model.draft = String(repeating: "x", count: 32_768)
        XCTAssertThrowsError(try model.acceptIncomingText("Incoming"))
        XCTAssertEqual(model.draft, String(repeating: "x", count: 32_768))
        XCTAssertFalse(model.isGenerating)
    }

    private func fixture() async throws -> (AppModel, SQLiteConversationStore, ControlledTokenSource) {
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("test.sqlite"))
        let attachmentService = try AttachmentService(directory: root.appendingPathComponent("Attachments"))
        let modelStore = try LocalModelStore(root: root.appendingPathComponent("Models"))
        let source = ControlledTokenSource()
        let provider = ControlledProvider(source: source)
        let model = AppModel(store: store, attachmentService: attachmentService, modelStore: modelStore, defaults: defaults)
        model.replaceProviders([ProviderOption(id: "controlled-test", title: "Test provider", detail: "Test only", provider: provider)])
        return (model, store, source)
    }

    private func waitFor(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { XCTFail("Timed out waiting for observable state"); throw WaitError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private enum WaitError: Error { case timeout }

private struct ControlledProvider: AIProvider {
    let id = "controlled-test"
    let displayName = "Controlled test provider"
    let source: ControlledTokenSource
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> { await source.subscribe(request) }
}

private actor ControlledTokenSource {
    private let pair = AsyncThrowingStream<String, Error>.makeStream()
    private(set) var hasSubscriber = false
    private(set) var lastRequest: GenerationRequest?
    func subscribe(_ request: GenerationRequest) -> AsyncThrowingStream<String, Error> { lastRequest = request; hasSubscriber = true; return pair.stream }
    func emit(_ value: String) { pair.continuation.yield(value) }
    func finish() { pair.continuation.finish() }
}
