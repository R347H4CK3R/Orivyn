import XCTest
import Observation
import SQLite3
@testable import JarvisEVO

/// Exercises AppModel's real submission, SQLite persistence and streaming path.
/// Only AIProvider's external token boundary is controlled. No frontend replies.
@MainActor
final class VoiceAppModelTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "JarvisEVO.VoiceAppModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func testVoiceWaitsForCompletePersistedResponseAndOwnsFirstCreatedConversation() async throws {
        let (model, store, source) = try fixture()
        let owner = UUID()
        let ticket = try model.makeVoiceTurnTicket(ownerID: owner)
        XCTAssertNil(model.selectedConversationID)
        var returned = false
        let operation = Task { let text = try await model.sendVoice("Question", ticket: ticket); returned = true; return text }
        try await waitFor { await source.subscriptions == 1 }
        XCTAssertTrue(model.activeVoiceTurn === ticket)
        XCTAssertEqual(ticket.ownerID, owner)
        XCTAssertEqual(model.selectedConversationID, ticket.conversationID)
        let savedQuestion = try await store.load(id: ticket.conversationID)
        XCTAssertEqual(savedQuestion?.messages.first?.content, "Question")
        await source.emit("Actual ")
        try await waitFor { model.activeConversation?.messages.last?.content == "Actual " }
        XCTAssertFalse(returned)
        await source.emit("response")
        await source.finish()
        let result = try await operation.value
        XCTAssertEqual(result, "Actual response")
        let saved = try await store.load(id: ticket.conversationID)
        XCTAssertEqual(saved?.messages.last?.content, "Actual response")
        XCTAssertEqual(saved?.messages.last?.state, .complete)
        XCTAssertNil(model.activeVoiceTurn)
        XCTAssertFalse(model.isGenerating)
    }

    func testAlreadyCancelledSendDoesNotChangeDraftOrPersistAnyTurn() async throws {
        let (model, store, source) = try fixture()
        model.draft = "Existing draft"
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let operation = Task { try await model.sendVoice("Never sent", ticket: ticket) }
        operation.cancel() // Same actor, with no suspension before cancelling.
        await assertCancellation(operation)
        XCTAssertEqual(model.draft, "Existing draft")
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertNil(model.selectedConversationID)
        let saved = try await store.list(includeArchived: true)
        let calls = await source.subscriptions
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(calls, 0)
    }

    func testTicketCancelledBeforeQueuedSendNeverMutatesOrPersists() async throws {
        let (model, store, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let operation = Task { try await model.sendVoice("Cancelled ticket", ticket: ticket) }
        model.cancelVoiceTurn(ticket)
        await assertCancellation(operation)
        XCTAssertTrue(model.conversations.isEmpty)
        let saved = try await store.list(includeArchived: true)
        let calls = await source.subscriptions
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(calls, 0)
    }

    func testStopAfterSubmissionButBeforeGenerationTaskSkipsInitialPersistence() async throws {
        let (model, store, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        // Observe the real synchronous generation transition, before its Task can
        // start. No storage stub or scheduling sleep determines this cancellation.
        withObservationTracking {
            _ = model.isGenerating
        } onChange: {
            MainActor.assumeIsolated { model.cancelVoiceTurn(ticket) }
        }
        let operation = Task { try await model.sendVoice("Restore unsaved speech", ticket: ticket) }
        await assertCancellation(operation)
        XCTAssertEqual(model.draft, "Restore unsaved speech")
        XCTAssertEqual(model.activeConversation?.messages.count, 0)
        let saved = try await store.list(includeArchived: true)
        let calls = await source.subscriptions
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(calls, 0)
    }

    func testCancellationDuringResponsePersistsPartialAsInterruptedAndNeverReturnsSuccess() async throws {
        let (model, store, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let operation = Task { try await model.sendVoice("Question", ticket: ticket) }
        try await waitFor { await source.subscriptions == 1 }
        await source.emit("Partial")
        try await waitFor { model.activeConversation?.messages.last?.content == "Partial" }
        model.cancelVoiceTurn(ticket)
        await assertCancellation(operation)
        let saved = try await store.load(id: ticket.conversationID)
        XCTAssertEqual(saved?.messages.last?.content, "Partial")
        XCTAssertEqual(saved?.messages.last?.state, .interrupted)
        XCTAssertFalse(model.isGenerating)
    }

    func testCancellingAwaitingCallerCancelsOnlyItsGeneration() async throws {
        let (model, store, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let operation = Task { try await model.sendVoice("Question", ticket: ticket) }
        try await waitFor { await source.subscriptions == 1 }
        operation.cancel()
        await assertCancellation(operation)
        let saved = try await store.load(id: ticket.conversationID)
        XCTAssertEqual(saved?.messages.last?.state, .interrupted)
        XCTAssertFalse(model.isGenerating)
    }

    func testProviderFailureIsThrownAndFailedResponseIsPersisted() async throws {
        let (model, store, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let operation = Task { try await model.sendVoice("Question", ticket: ticket) }
        try await waitFor { await source.subscriptions == 1 }
        await source.emit("Incomplete")
        await source.fail(ProviderError.rejected("Provider failed"))
        do { _ = try await operation.value; XCTFail("A failed model response must not be spoken") }
        catch { XCTAssertEqual(error.localizedDescription, "Provider failed") }
        let saved = try await store.load(id: ticket.conversationID)
        XCTAssertEqual(saved?.messages.last?.state, .failed)
        XCTAssertFalse(model.isGenerating)
    }

    func testWhitespaceOnlyResponseIsRejectedRatherThanReadAloud() async throws {
        let (model, store, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let operation = Task { try await model.sendVoice("Question", ticket: ticket) }
        try await waitFor { await source.subscriptions == 1 }
        await source.emit(" \n ")
        await source.finish()
        do { _ = try await operation.value; XCTFail("Empty model response must fail") }
        catch { XCTAssertEqual(error.localizedDescription, ProviderError.emptyResponse.localizedDescription) }
        let saved = try await store.load(id: ticket.conversationID)
        XCTAssertEqual(saved?.messages.last?.state, .failed)
    }

    func testInitialSQLiteValidationFailureRestoresDraftAndDoesNotCallProvider() async throws {
        let (model, store, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let text = String(repeating: "x", count: 1_000_001)
        do { _ = try await model.sendVoice(text, ticket: ticket); XCTFail("Invalid turn must not reach inference") }
        catch { XCTAssertEqual(error.localizedDescription, ConversationError.tooLarge.localizedDescription) }
        XCTAssertEqual(model.draft, text)
        XCTAssertEqual(model.activeConversation?.messages.count, 0)
        let saved = try await store.list(includeArchived: true)
        let calls = await source.subscriptions
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(model.isGenerating)
    }

    func testFinalSaveFailureCannotReturnSuccessfulText() async throws {
        let (model, store, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let operation = Task { try await model.sendVoice("Question", ticket: ticket) }
        try await waitFor { await source.subscriptions == 1 }
        // Real SQLite rejects only the final complete assistant snapshot. Initial
        // persistence and failed-state recovery still use the unmodified store.
        try installCompletionFailureTrigger()
        await source.emit("Generated but not durably complete")
        await source.finish()
        do { _ = try await operation.value; XCTFail("Final save failure must not become spoken success") }
        catch { XCTAssertTrue(error is DatabaseError) }
        let saved = try await store.load(id: ticket.conversationID)
        XCTAssertEqual(saved?.messages.last?.content, "Generated but not durably complete")
        XCTAssertEqual(saved?.messages.last?.state, .failed)
        XCTAssertFalse(model.isGenerating)
    }

    func testDraftEditAfterTicketCreationIsNotOverwritten() async throws {
        let (model, _, source) = try fixture()
        model.draft = "Before"
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        model.draft = "User edited this"
        do { _ = try await model.sendVoice("Outdated speech", ticket: ticket); XCTFail("Changed draft must invalidate ticket") }
        catch { XCTAssertTrue(error is VoiceTurnError) }
        XCTAssertEqual(model.draft, "User edited this")
        XCTAssertTrue(model.conversations.isEmpty)
        let calls = await source.subscriptions
        XCTAssertEqual(calls, 0)
    }

    func testReplacingProviderWithSameIDInvalidatesUnsubmittedTicket() async throws {
        let (model, _, originalSource) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let replacement = VoiceTokenSource()
        model.replaceProviders([ProviderOption(id: "voice-test", title: "Replacement", detail: "Test only", provider: VoiceControlledProvider(source: replacement))])
        do { _ = try await model.sendVoice("Old configuration", ticket: ticket); XCTFail("Same ID does not authorize changed provider configuration") }
        catch { XCTAssertTrue(error is VoiceTurnError) }
        let originalCalls = await originalSource.subscriptions
        let newCalls = await replacement.subscriptions
        XCTAssertEqual(originalCalls, 0)
        XCTAssertEqual(newCalls, 0)
        XCTAssertTrue(model.conversations.isEmpty)
    }

    func testContextChangedBeforeSendRejectsStaleTicketWithoutClearingNewDraft() async throws {
        let (model, store, source) = try fixture()
        let stale = try model.makeVoiceTurnTicket(ownerID: UUID())
        await model.newConversation()
        let selected = model.selectedConversationID
        model.draft = "New chat draft"
        do { _ = try await model.sendVoice("Stale speech", ticket: stale); XCTFail("Stale context must fail") }
        catch { XCTAssertTrue(error is VoiceTurnError) }
        XCTAssertEqual(model.selectedConversationID, selected)
        XCTAssertEqual(model.draft, "New chat draft")
        XCTAssertTrue(model.conversations.allSatisfy { $0.messages.isEmpty })
        let saved = try await store.list(includeArchived: true)
        let calls = await source.subscriptions
        XCTAssertTrue(saved.allSatisfy { $0.messages.isEmpty })
        XCTAssertEqual(calls, 0)
    }

    func testProviderChangeBeforeSendRejectsStaleTicket() async throws {
        let (model, _, source) = try fixture()
        let stale = try model.makeVoiceTurnTicket(ownerID: UUID())
        model.selectedProviderID = "another-provider"
        do { _ = try await model.sendVoice("Stale speech", ticket: stale); XCTFail("Changed provider must invalidate ticket") }
        catch { XCTAssertTrue(error is VoiceTurnError) }
        XCTAssertTrue(model.conversations.isEmpty)
        let calls = await source.subscriptions
        XCTAssertEqual(calls, 0)
    }

    func testNewChatDuringVoiceCancelsOriginatingTurnWithoutMovingLateOutput() async throws {
        let (model, store, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let operation = Task { try await model.sendVoice("Original", ticket: ticket) }
        try await waitFor { await source.subscriptions == 1 }
        await model.newConversation()
        let selected = try XCTUnwrap(model.selectedConversationID)
        XCTAssertNotEqual(selected, ticket.conversationID)
        await source.emit("Late response")
        await source.finish()
        await assertCancellation(operation)
        XCTAssertEqual(model.selectedConversationID, selected)
        XCTAssertTrue(model.activeConversation?.messages.isEmpty == true)
        let original = try await store.load(id: ticket.conversationID)
        XCTAssertEqual(original?.messages.last?.state, .interrupted)
    }

    func testProviderSwitchDuringVoiceRejectsLateCompletion() async throws {
        let (model, store, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let operation = Task { try await model.sendVoice("Question", ticket: ticket) }
        try await waitFor { await source.subscriptions == 1 }
        model.selectedProviderID = "another-provider"
        await source.emit("Late response")
        await source.finish()
        await assertCancellation(operation)
        let saved = try await store.load(id: ticket.conversationID)
        XCTAssertEqual(saved?.messages.last?.state, .interrupted)
    }

    func testLateStopForFinishedVoiceTicketCannotCancelManualGeneration() async throws {
        let (model, _, source) = try fixture()
        let old = try model.makeVoiceTurnTicket(ownerID: UUID())
        let voice = Task { try await model.sendVoice("Voice", ticket: old) }
        try await waitFor { await source.subscriptions == 1 }
        await source.emit("Voice answer")
        await source.finish()
        _ = try await voice.value
        model.draft = "Manual question"
        model.send()
        try await waitFor { await source.subscriptions == 2 }
        model.cancelVoiceTurn(old)
        await source.emit("Manual answer")
        await source.finish()
        try await waitFor { !model.isGenerating }
        XCTAssertEqual(model.activeConversation?.messages.last?.content, "Manual answer")
        XCTAssertEqual(model.activeConversation?.messages.last?.state, .complete)
    }

    func testLateStopForOldTicketCannotCancelNewVoiceFromSameOwner() async throws {
        let (model, _, source) = try fixture()
        let owner = UUID()
        let old = try model.makeVoiceTurnTicket(ownerID: owner)
        let first = Task { try await model.sendVoice("First", ticket: old) }
        try await waitFor { await source.subscriptions == 1 }
        await source.emit("First answer")
        await source.finish()
        _ = try await first.value
        let current = try model.makeVoiceTurnTicket(ownerID: owner)
        let second = Task { try await model.sendVoice("Second", ticket: current) }
        try await waitFor { await source.subscriptions == 2 }
        model.cancelVoiceTurn(old)
        XCTAssertTrue(model.activeVoiceTurn === current)
        await source.emit("Second answer")
        await source.finish()
        let result = try await second.value
        XCTAssertEqual(result, "Second answer")
    }

    func testEditedComposerDuringVoiceIsNotClearedByLateCompletion() async throws {
        let (model, _, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let operation = Task { try await model.sendVoice("Voice question", ticket: ticket) }
        try await waitFor { await source.subscriptions == 1 }
        model.draft = "New text typed by the user"
        await source.emit("Late answer")
        await source.finish()
        do { _ = try await operation.value; XCTFail("Changed composer must not authorize a voice continuation") }
        catch { XCTAssertTrue(error is VoiceTurnError) }
        XCTAssertEqual(model.draft, "New text typed by the user")
    }

    func testManualImmediateStopRestoresDraftWithoutInitialPersistence() async throws {
        let (model, store, source) = try fixture()
        model.draft = "Manual draft"
        model.send()
        model.stop()
        try await waitFor { !model.isGenerating }
        XCTAssertEqual(model.draft, "Manual draft")
        XCTAssertEqual(model.activeConversation?.messages.count, 0)
        let saved = try await store.list(includeArchived: true)
        let calls = await source.subscriptions
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(calls, 0)
    }

    func testVoicePreflightDoesNotCancelInFlightAttachmentOrReleaseItsReservation() async throws {
        let service = try AttachmentService(directory: root.appendingPathComponent("main/Attachments"))
        let importer = VoiceHoldingImporter(service: service)
        let (model, _, _) = try fixture(importer: importer)
        let file = root.appendingPathComponent("importing.txt")
        try Data("Real local attachment".utf8).write(to: file)
        let importing = Task { await model.addAttachments(from: [file]) }
        try await waitFor { await importer.isHolding }
        XCTAssertThrowsError(try model.makeVoiceTurnTicket(ownerID: UUID()))
        XCTAssertTrue(model.isImportingAttachments)
        XCTAssertEqual(model.availableAttachmentSlots, 3)
        await importer.release()
        await importing.value
        XCTAssertFalse(model.isImportingAttachments)
        XCTAssertEqual(model.pendingAttachments.count, 1)
        let attachment = try XCTUnwrap(model.pendingAttachments.first)
        XCTAssertNotNil(model.attachmentService.url(for: attachment))
    }

    func testPendingAttachmentsAreNotConsumedByVoiceSubmission() async throws {
        let (model, _, _) = try fixture()
        let file = root.appendingPathComponent("keep.txt")
        try Data("Keep this attachment".utf8).write(to: file)
        let attachment = try model.attachmentService.importFile(at: file)
        model.pendingAttachments = [attachment]
        model.draft = "Keep draft"
        XCTAssertThrowsError(try model.makeVoiceTurnTicket(ownerID: UUID()))
        XCTAssertEqual(model.pendingAttachments, [attachment])
        XCTAssertEqual(model.draft, "Keep draft")
        XCTAssertNotNil(model.attachmentService.url(for: attachment))
    }

    func testTicketCannotBeReusedOrAppliedToAnotherAppModel() async throws {
        let (model, _, source) = try fixture()
        let ticket = try model.makeVoiceTurnTicket(ownerID: UUID())
        let (other, _, _) = try fixture(name: "other")
        do { _ = try await other.sendVoice("Wrong owner", ticket: ticket); XCTFail("Ticket belongs to another AppModel") }
        catch { XCTAssertTrue(error is VoiceTurnError) }
        let operation = Task { try await model.sendVoice("Once", ticket: ticket) }
        try await waitFor { await source.subscriptions == 1 }
        await source.emit("Answer")
        await source.finish()
        _ = try await operation.value
        do { _ = try await model.sendVoice("Twice", ticket: ticket); XCTFail("Ticket must be single use") }
        catch { XCTAssertTrue(error is VoiceTurnError) }
        XCTAssertEqual(model.activeConversation?.messages.count, 2)
    }

    private func installCompletionFailureTrigger() throws {
        var database: OpaquePointer?
        let path = root.appendingPathComponent("main/test.sqlite").path
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw VoiceBridgeWaitError.storageSetup
        }
        defer { sqlite3_close(database) }
        let sql = """
        CREATE TRIGGER reject_complete_voice BEFORE UPDATE ON conversations
        WHEN json_extract(CAST(NEW.payload AS TEXT), '$.messages[#-1].state') = 'complete'
        BEGIN SELECT RAISE(ABORT, 'Test final save rejection'); END;
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw VoiceBridgeWaitError.storageSetup }
    }

    private func fixture(name: String = "main", importer: (any AttachmentImporting)? = nil) throws -> (AppModel, SQLiteConversationStore, VoiceTokenSource) {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        let store = try SQLiteConversationStore(url: directory.appendingPathComponent("test.sqlite"))
        let attachments = try AttachmentService(directory: directory.appendingPathComponent("Attachments"))
        let models = try LocalModelStore(root: directory.appendingPathComponent("Models"))
        let source = VoiceTokenSource()
        let model = AppModel(store: store, attachmentService: attachments, modelStore: models, defaults: defaults, attachmentImporter: importer)
        model.replaceProviders([ProviderOption(id: "voice-test", title: "Test", detail: "Test only", provider: VoiceControlledProvider(source: source))])
        return (model, store, source)
    }

    private func assertCancellation(_ operation: Task<String, any Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation.value; XCTFail("Cancelled voice turn returned success", file: file, line: line) }
        catch { XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)", file: file, line: line) }
    }

    private func waitFor(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { XCTFail("Voice model state did not settle"); throw VoiceBridgeWaitError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private struct VoiceControlledProvider: AIProvider {
    let id = "voice-test"
    let displayName = "Controlled voice test provider"
    let source: VoiceTokenSource
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> { await source.subscribe() }
}

private actor VoiceTokenSource {
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private(set) var subscriptions = 0
    func subscribe() -> AsyncThrowingStream<String, Error> {
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        continuation = pair.continuation
        subscriptions += 1
        return pair.stream
    }
    func emit(_ text: String) { continuation?.yield(text) }
    func finish() { continuation?.finish() }
    func fail(_ error: any Error) { continuation?.finish(throwing: error) }
}

private enum VoiceBridgeWaitError: Error { case timeout, storageSetup }

/// Holds delivery after the real file importer succeeds; never fabricates files.
private actor VoiceHoldingImporter: AttachmentImporting {
    private let importer: LocalAttachmentImporter
    private var continuation: CheckedContinuation<Void, Never>?
    var isHolding: Bool { continuation != nil }
    init(service: AttachmentService) { importer = LocalAttachmentImporter(service: service) }
    func importAttachment(_ source: AttachmentImportSource) async throws -> ChatAttachment {
        let attachment = try await importer.importAttachment(source)
        await withCheckedContinuation { continuation = $0 }
        return attachment
    }
    func release() { continuation?.resume(); continuation = nil }
}
