import XCTest
import SQLite3
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

    func testMemorySaveReportsFailureAndStableIDRetryDoesNotDuplicate() async throws {
        let (model, store, _) = try await fixture()
        let id = UUID()
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("test.sqlite").path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "CREATE TRIGGER fail_memory BEFORE INSERT ON memory BEGIN SELECT RAISE(ABORT, 'injected failure'); END;", nil, nil, nil), SQLITE_OK)
        let failed = await model.saveMemory(id: id, content: "Retain my edited text")
        XCTAssertFalse(failed)
        XCTAssertTrue(model.memories.isEmpty)
        XCTAssertEqual(sqlite3_exec(connection, "DROP TRIGGER fail_memory", nil, nil, nil), SQLITE_OK)
        let saved = await model.saveMemory(id: id, content: "Retain my edited text")
        XCTAssertTrue(saved)
        let retried = await model.saveMemory(id: id, content: "Updated safely")
        XCTAssertTrue(retried)
        let notes = try await store.memories()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.id, id)
        XCTAssertEqual(notes.first?.content, "Updated safely")
        let invalid = await model.saveMemory(content: String(repeating: "x", count: 4001))
        XCTAssertFalse(invalid)
        let oversizedCluster = "a" + String(repeating: "\u{0301}", count: 20_000)
        let byteInvalid = await model.saveMemory(content: oversizedCluster)
        XCTAssertFalse(byteInvalid)
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

    func testLargeMemoryLibraryUsesBoundedRelevantContextWithoutDeletingNotes() async throws {
        let (model, store, source) = try await fixture()
        let important = await model.saveMemory(content: "My espresso preference is decaf oat milk.")
        XCTAssertTrue(important)
        for index in 0..<25 {
            let saved = await model.saveMemory(content: "Unrelated note \(index): " + String(repeating: "x", count: 3000))
            XCTAssertTrue(saved)
        }
        model.draft = "What is my espresso preference?"
        model.send()
        try await waitFor { await source.hasSubscriber }
        let captured = await source.lastRequest
        let request = try XCTUnwrap(captured)
        XCTAssertTrue(request.systemPrompt.contains("decaf oat milk"))
        XCTAssertLessThan(request.systemPrompt.utf8.count, 8_000)
        XCTAssertFalse(request.systemPrompt.contains(String(repeating: "x", count: 1000)))
        XCTAssertNotNil(model.lastMemoryContextSummary)
        let retained = try await store.memories()
        XCTAssertEqual(retained.count, 26)
        model.stop()
        try await waitFor { !model.isGenerating }
    }

    func testSavedBehaviorReachesActualGenerationRequest() async throws {
        let (model, _, source) = try await fixture()
        var behavior = ResponseBehavior(); behavior.instructions = "Use concise explanations."; behavior.style = "Efficient"
        try model.workspace.saveBehavior(behavior)
        model.draft = "Test preferences"; model.send()
        try await waitFor { await source.hasSubscriber }
        let request = await source.lastRequest
        XCTAssertTrue(request?.systemPrompt.contains("You are Jarvis in Orivyn") == true)
        XCTAssertTrue(request?.systemPrompt.contains("Bundled capability knowledge schema 1") == true)
        XCTAssertTrue(request?.systemPrompt.contains("self-repair [notAvailable]") == true)
        XCTAssertTrue(request?.systemPrompt.contains("https://github.com/R347H4CK3R/Orivyn") == true)
        XCTAssertTrue(request?.systemPrompt.contains("Use concise explanations.") == true)
        XCTAssertTrue(request?.systemPrompt.contains("Style: Efficient") == true)
        XCTAssertTrue(request?.systemPrompt.contains("Do not invent tools") == true)
        XCTAssertTrue(request?.systemPrompt.contains("do the useful part first") == true)
        XCTAssertTrue(request?.systemPrompt.contains("without a recorded result") == true)
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

    func testConciseQwenModeDefaultsOffPersistsAndReachesRequest() async throws {
        let (model, _, source) = try await fixture()
        XCTAssertFalse(model.conciseQwen3)
        model.conciseQwen3 = true
        XCTAssertTrue(defaults.bool(forKey: "orivyn.conciseQwen3"))
        model.draft = "Test response mode"; model.send()
        try await waitFor { await source.hasSubscriber }
        let request = await source.lastRequest
        XCTAssertEqual(request?.conciseQwen3, true)
        model.stop(); try await waitFor { !model.isGenerating }
        let (reopened, _, _) = try await fixture()
        XCTAssertTrue(reopened.conciseQwen3)
    }

    func testOwnedPendingRemovalBeforeBootstrapPreservesUnknownPersistedFiles() async throws {
        let (model, store, _) = try await fixture()
        let source = root.appendingPathComponent("saved-before-bootstrap.txt")
        try Data("Saved file must survive".utf8).write(to: source)
        let savedAttachment = try model.attachmentService.importFile(at: source)
        try await store.save(Conversation(messages: [ChatMessage(role: .user, content: "Saved", attachments: [savedAttachment])]))
        XCTAssertTrue(model.conversations.isEmpty, "The app has not loaded persisted references")
        await model.addAttachments(from: [source])
        let fresh = try XCTUnwrap(model.pendingAttachments.first)
        XCTAssertNotEqual(fresh.relativePath, savedAttachment.relativePath)
        model.removePendingAttachment(fresh)
        XCTAssertNil(model.attachmentService.url(for: fresh), "Fresh owned rollback is synchronous")
        XCTAssertNotNil(model.attachmentService.url(for: savedAttachment), "Unknown persisted bytes are not swept")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: model.attachmentService.directory.path).count, 1)
    }

    func testOwnedImportsAfterFailedBootstrapCanBeRemovedWithoutSweepingSavedFiles() async throws {
        let (model, store, _) = try await fixture()
        let source = root.appendingPathComponent("saved-before-failure.txt")
        try Data("Keep despite unreadable history".utf8).write(to: source)
        let savedAttachment = try model.attachmentService.importFile(at: source)
        try await store.save(Conversation(messages: [ChatMessage(role: .user, content: "Saved", attachments: [savedAttachment])]))
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("test.sqlite").path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "UPDATE conversations SET payload = x'00'", nil, nil, nil), SQLITE_OK)
        await model.bootstrap()
        XCTAssertNotNil(model.errorMessage)
        await model.addAttachments(from: [source])
        let fresh = try XCTUnwrap(model.pendingAttachments.first)
        model.clearPendingAttachments()
        XCTAssertNil(model.attachmentService.url(for: fresh))
        XCTAssertNotNil(model.attachmentService.url(for: savedAttachment))
    }

    func testAttachmentCleanupRetainsFilesUntilHistoryHasLoaded() async throws {
        let (model, store, _) = try await fixture()
        let source = root.appendingPathComponent("original.txt")
        try Data("Original saved attachment".utf8).write(to: source)
        let attachment = try model.attachmentService.importFile(at: source)
        let saved = Conversation(messages: [ChatMessage(role: .user, content: "Saved", attachments: [attachment])])
        try await store.save(saved)
        // A composer cleanup before bootstrap has no authority over persisted files.
        model.removePendingAttachment(attachment)
        XCTAssertNotNil(model.attachmentService.url(for: attachment))
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("test.sqlite").path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "UPDATE conversations SET payload = x'00'", nil, nil, nil), SQLITE_OK)
        await model.bootstrap()
        XCTAssertNotNil(model.errorMessage)
        model.clearPendingAttachments()
        XCTAssertNotNil(model.attachmentService.url(for: attachment))
        // Recovery restores cleanup eligibility, but keeps every persisted reference.
        try await store.save(saved)
        await model.bootstrap()
        XCTAssertEqual(model.conversations.count, 1)
        XCTAssertNotNil(model.attachmentService.url(for: attachment))
        let orphan = try model.attachmentService.importFile(at: source)
        model.removePendingAttachment(orphan)
        XCTAssertNil(model.attachmentService.url(for: orphan))
        XCTAssertNotNil(model.attachmentService.url(for: attachment))
    }

    func testFailedHistoryRefreshInvalidatesPreviousCleanupSnapshot() async throws {
        let (model, store, _) = try await fixture()
        await model.bootstrap()
        let source = root.appendingPathComponent("later.txt")
        try Data("Added after snapshot".utf8).write(to: source)
        let attachment = try model.attachmentService.importFile(at: source)
        let saved = Conversation(messages: [ChatMessage(role: .user, content: "Later", attachments: [attachment])])
        try await store.save(saved)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("test.sqlite").path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "UPDATE conversations SET payload = x'00'", nil, nil, nil), SQLITE_OK)
        await model.bootstrap()
        model.clearPendingAttachments()
        XCTAssertNotNil(model.attachmentService.url(for: attachment))
    }

    func testFailedImportRetainsFilesUntilReloadOrExplicitDeleteAll() async throws {
        let (model, store, _) = try await fixture()
        await model.bootstrap()
        let source = root.appendingPathComponent("retain.txt")
        try Data("Keep until a complete snapshot".utf8).write(to: source)
        let attachment = try model.attachmentService.importFile(at: source)
        let saved = Conversation(messages: [ChatMessage(role: .user, content: "Saved", attachments: [attachment])])
        try await store.save(saved)
        // Keep a valid stale snapshot: failed import must not sweep against it.
        let invalid = root.appendingPathComponent("invalid.json")
        try Data("not JSON".utf8).write(to: invalid)
        await model.importHistory(from: invalid)
        model.clearPendingAttachments()
        XCTAssertNotNil(model.attachmentService.url(for: attachment))
        await model.deleteAllContent()
        XCTAssertNil(model.attachmentService.url(for: attachment))
        let remaining = try await store.list(includeArchived: true)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testChatPersistsOnlyAnswerAndProvidesCodingPolicy() async throws {
        let (model, store, source) = try await fixture()
        model.draft = "Write a simple Python script"
        model.send()
        try await waitFor { await source.hasSubscriber }
        let request = await source.lastRequest
        XCTAssertTrue(request?.systemPrompt.contains("write Python") == true)
        let id = try XCTUnwrap(model.selectedConversationID)
        await source.emit("<thi")
        await source.emit("nk>private analysis</thi")
        await source.emit("nk>\nprint('Hello')")
        await source.finish()
        try await waitFor { !model.isGenerating }
        let saved = try await store.load(id: id)
        XCTAssertEqual(model.activeConversation?.messages.last?.content, "\nprint('Hello')")
        XCTAssertEqual(saved?.messages.last?.content, "\nprint('Hello')")
        XCTAssertEqual(saved?.messages.last?.state, .complete)
    }

    func testReasoningOnlyResponseIsFailedNotCompleted() async throws {
        let (model, store, source) = try await fixture()
        model.draft = "Write Python"
        model.send()
        try await waitFor { await source.hasSubscriber }
        let id = try XCTUnwrap(model.selectedConversationID)
        await source.emit("<think>unfinished internal output")
        await source.finish()
        try await waitFor { !model.isGenerating }
        let saved = try await store.load(id: id)
        XCTAssertEqual(saved?.messages.last?.content, "")
        XCTAssertEqual(saved?.messages.last?.state, .failed)
    }

    func testExplicitLocalReadPersistsWithoutCallingSelectedProvider() async throws {
        let (model, store, source) = try await fixture()
        model.draft = "list installed models"
        model.send()
        try await waitFor { !model.isGenerating }
        let id = try XCTUnwrap(model.selectedConversationID)
        let saved = try await store.load(id: id)
        XCTAssertEqual(saved?.messages.first?.content, "list installed models")
        XCTAssertEqual(saved?.messages.last?.state, .complete)
        XCTAssertTrue(saved?.messages.last?.content.contains("Completed local read: list_models") == true)
        let contacted = await source.hasSubscriber
        XCTAssertFalse(contacted)
    }

    func testHistoricalLocalCommandDoesNotExecuteForUnrelatedCurrentMessage() async throws {
        let (model, store, source) = try await fixture()
        let history = Conversation(messages: [ChatMessage(role: .user, content: "list installed models")])
        try await store.save(history)
        await model.bootstrap()
        model.replaceProviders([ProviderOption(id: "controlled-test", title: "Test provider", detail: "Test only",
            provider: ControlledProvider(source: source))])
        model.selectedConversationID = history.id
        model.draft = "Explain what a model is"
        model.send()
        try await waitFor { await source.hasSubscriber }
        await source.emit("Explanation")
        await source.finish()
        try await waitFor { !model.isGenerating }
        XCTAssertEqual(model.activeConversation?.messages.last?.content, "Explanation")
    }

    func testAmbiguousLocalCommandRemainsOrdinaryConversation() async throws {
        let (model, _, source) = try await fixture()
        model.draft = "list installed models and delete one"
        model.send()
        try await waitFor { await source.hasSubscriber }
        await source.finish()
        try await waitFor { !model.isGenerating }
        XCTAssertFalse(model.activeConversation?.messages.last?.content.contains("Completed local read") == true)
    }

    func testSuccessfulPluginHandoffPreservesDraftAndAttachmentWithoutSending() async throws {
        let (model, _, source) = try await fixture()
        let client = PluginResultAppClient()
        model.configurePlugins(directory: root.appendingPathComponent("Plugins"), clientFactory: { _, _ in client })
        let broker = try XCTUnwrap(model.plugins)
        try await broker.connect(endpointText: "https://example.invalid/mcp", token: "")
        try broker.installConnection(rememberToken: false)
        let file = root.appendingPathComponent("plugin-success-attachment.txt")
        try Data("Synthetic attachment".utf8).write(to: file)
        model.pendingAttachments = [try model.attachmentService.importFile(at: file)]
        model.draft = "My unsent draft"
        let attachments = model.pendingAttachments, history = model.conversations
        let review = try broker.prepareReview(toolName: "fixture.read", argumentText: "{}")
        try await broker.execute(reviewID: review.id, conversationContext: model.pluginResultConversationContext)
        // Editing in the same conversation before explicit handoff is preserved, not overwritten.
        model.draft += " with a later edit"
        try model.addPluginResultToDraft(executionID: XCTUnwrap(broker.completedResult).executionID)
        XCTAssertTrue(model.draft.hasPrefix("My unsent draft with a later edit\n\n"))
        XCTAssertTrue(model.draft.contains("Synthetic server result"))
        XCTAssertEqual(model.pendingAttachments, attachments)
        XCTAssertEqual(model.conversations, history)
        XCTAssertFalse(model.isGenerating)
        let hasSubscriber = await source.hasSubscriber; XCTAssertFalse(hasSubscriber)
        let calls = await client.calls; XCTAssertEqual(calls, 1)
    }

    func testPluginProviderContextChangesOnSelectionRoundTripAndProviderReplacement() async throws {
        let (model, _, _) = try await fixture()
        let initial = model.pluginProposalProviderContext, selected = model.selectedProviderID
        model.selectedProviderID = "another-synthetic-provider"
        model.selectedProviderID = selected
        XCTAssertNotEqual(model.pluginProposalProviderContext, initial)
        let roundTrip = model.pluginProposalProviderContext
        model.replaceProviders(model.providers)
        XCTAssertNotEqual(model.pluginProposalProviderContext, roundTrip)
    }

    func testPluginHandoffContextInvalidatesOnConversationRoundTripAndFailurePreservesComposer() async throws {
        let (model, _, _) = try await fixture()
        let original = model.pluginResultConversationContext
        let selected = model.selectedConversationID
        model.draft = "Unsent user text"
        let file = root.appendingPathComponent("plugin-preserved-attachment.txt")
        try Data("Synthetic attachment to preserve".utf8).write(to: file)
        model.pendingAttachments = [try model.attachmentService.importFile(at: file)]
        let attachments = model.pendingAttachments
        model.selectedConversationID = UUID()
        model.selectedConversationID = selected
        XCTAssertNotEqual(model.pluginResultConversationContext, original)
        XCTAssertThrowsError(try model.addPluginResultToDraft(executionID: UUID()))
        XCTAssertEqual(model.draft, "Unsent user text")
        XCTAssertEqual(model.pendingAttachments, attachments)
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


private actor PluginResultAppClient: PluginMCPClient {
    private(set) var calls = 0
    func initialize() async throws -> MCPServerInfo { .init(name: "Synthetic", version: "1") }
    func listTools() async throws -> [MCPToolDefinition] {
        [.init(name: "fixture.read", inputSchema: try MCPToolSchema(json: .object(["type": .string("object")])))]
    }
    func callTool(named: String, arguments: MCPJSONValue) async throws -> MCPToolCallResult {
        calls += 1
        return .init(content: [.text("Synthetic server result")], structuredContent: nil, isError: false)
    }
    func cancelCurrentOperation() async {}
    func close() async {}
}
