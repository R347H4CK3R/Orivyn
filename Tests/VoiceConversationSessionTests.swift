import XCTest
@testable import JarvisEVO

/// Tests the production UI bridge, controller and SQLite AppModel together.
/// Only speech hardware and the provider token boundary are controlled here.
/// This is not evidence of audible speech, real microphone input or inference.
@MainActor
final class VoiceConversationSessionTests: XCTestCase {
    private var root: URL!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "JarvisEVO.SessionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func testPreflightWithoutModelDoesNotRequestAudioOrCreateConversation() throws {
        let (model, _, _) = try fixture(provider: false)
        let audio = SessionAudio()
        let session = VoiceConversationSession(model: model, audio: audio)
        XCTAssertThrowsError(try session.start())
        XCTAssertEqual(audio.starts, 0)
        XCTAssertFalse(session.controller.isActive)
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertNil(model.activeVoiceTurn)
    }

    func testPendingFilesPreflightKeepsDraftAndFilesWithoutRequestingAudio() throws {
        let (model, _, _) = try fixture()
        let file = root.appendingPathComponent("kept.txt")
        try Data("Keep this file".utf8).write(to: file)
        let attachment = try model.attachmentService.importFile(at: file)
        model.pendingAttachments = [attachment]
        model.draft = "Existing idea"
        let audio = SessionAudio()
        let session = VoiceConversationSession(model: model, audio: audio)
        XCTAssertThrowsError(try session.start())
        XCTAssertEqual(model.draft, "Existing idea")
        XCTAssertEqual(model.pendingAttachments, [attachment])
        XCTAssertEqual(audio.starts, 0)
    }

    func testFinalTranscriptUsesFreshTicketAndAllowsItsOwnFirstSelection() async throws {
        let (model, store, source) = try fixture()
        model.draft = "Please"
        let audio = SessionAudio()
        let session = VoiceConversationSession(model: model, audio: audio)
        defer { session.stop() }
        try session.start()
        XCTAssertNil(model.activeVoiceTurn, "Microphone preflight must not acquire a generation.")
        try await waitFor { session.controller.state == .listening }
        audio.onTranscript?("explain this")
        XCTAssertEqual(model.draft, "Please explain this")
        audio.onFinalTranscript?("explain this clearly")
        try await waitFor { await source.subscriptions == 1 }
        let ticket = try XCTUnwrap(model.activeVoiceTurn)
        XCTAssertTrue(session.selectionChanged(from: nil, to: ticket.conversationID))
        XCTAssertTrue(session.controller.isActive)
        XCTAssertEqual(model.activeConversation?.messages.first?.content, "Please explain this clearly")
        await source.emit("Persisted answer")
        try await waitFor { model.activeConversation?.messages.last?.content == "Persisted answer" }
        XCTAssertTrue(audio.spoken.isEmpty, "Partial streamed tokens must not start speech.")
        await source.finish()
        try await waitFor { session.controller.state == .speaking }
        let saved = try await store.load(id: ticket.conversationID)
        XCTAssertEqual(saved?.messages.last?.state, .complete)
        XCTAssertEqual(audio.spoken, ["Persisted answer"])
        XCTAssertEqual(model.draft, "")
        audio.onPlaybackFinished?()
        try await waitFor { session.controller.state == .listening }
        XCTAssertEqual(audio.starts, 2)
    }

    func testOwnSelectionCanArriveAfterFastCompletionButOnlyOnce() async throws {
        let (model, _, source) = try fixture()
        let audio = SessionAudio()
        let session = VoiceConversationSession(model: model, audio: audio)
        defer { session.stop() }
        try session.start()
        try await waitFor { session.controller.state == .listening }
        audio.onFinalTranscript?("Question")
        try await waitFor { await source.subscriptions == 1 }
        let selected = try XCTUnwrap(model.selectedConversationID)
        await source.emit("Answer"); await source.finish()
        try await waitFor { session.controller.state == .speaking }
        XCTAssertNil(model.activeVoiceTurn)
        XCTAssertTrue(session.selectionChanged(from: nil, to: selected))
        XCTAssertTrue(session.controller.isActive)
        XCTAssertFalse(session.selectionChanged(from: nil, to: selected))
        XCTAssertFalse(session.controller.isActive)
    }

    func testFailedPartialReplyNeverReachesSpeech() async throws {
        let (model, store, source) = try fixture()
        let audio = SessionAudio()
        let session = VoiceConversationSession(model: model, audio: audio)
        defer { session.stop() }
        try session.start()
        try await waitFor { session.controller.state == .listening }
        audio.onFinalTranscript?("Question")
        try await waitFor { await source.subscriptions == 1 }
        let selected = try XCTUnwrap(model.selectedConversationID)
        await source.emit("Incomplete"); await source.fail()
        try await waitFor { session.controller.state == .failed }
        XCTAssertTrue(audio.spoken.isEmpty)
        let saved = try await store.load(id: selected)
        XCTAssertEqual(saved?.messages.last?.state, .failed)
    }

    func testExternalSelectionStopsVoiceAndOldStopCannotCancelLaterManualTurn() async throws {
        let (model, _, source) = try fixture()
        let audio = SessionAudio()
        let session = VoiceConversationSession(model: model, audio: audio)
        try session.start()
        try await waitFor { session.controller.state == .listening }
        audio.onFinalTranscript?("Voice question")
        try await waitFor { await source.subscriptions == 1 }
        XCTAssertFalse(session.selectionChanged(from: model.selectedConversationID, to: UUID()))
        try await waitFor { !model.isGenerating }
        XCTAssertFalse(session.controller.isActive)
        model.draft = "Later manual message"
        model.send()
        try await waitFor { await source.subscriptions == 2 }
        session.stop()
        XCTAssertTrue(model.isGenerating, "The old voice session does not own manual generation.")
        await source.emit("Manual answer"); await source.finish()
        try await waitFor { !model.isGenerating }
        XCTAssertEqual(model.activeConversation?.messages.last?.state, .complete)
        XCTAssertTrue(audio.spoken.isEmpty)
    }

    private func fixture(provider: Bool = true) throws -> (AppModel, SQLiteConversationStore, SessionTokens) {
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("test.sqlite"))
        let attachments = try AttachmentService(directory: root.appendingPathComponent("Attachments"))
        let models = try LocalModelStore(root: root.appendingPathComponent("Models"))
        let model = AppModel(offlineAutoSelection: false, store: store, attachmentService: attachments, modelStore: models, defaults: defaults)
        let source = SessionTokens()
        model.replaceProviders(provider ? [ProviderOption(id: "session-test", title: "Test boundary", detail: "Not real inference", provider: SessionProvider(source: source))] : [])
        return (model, store, source)
    }
    private func waitFor(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { XCTFail("UI voice bridge did not settle"); throw SessionTestError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private enum SessionTestError: Error { case timeout, failed }
private struct SessionProvider: AIProvider {
    let id = "session-test"
    let displayName = "Controlled session test provider"
    let source: SessionTokens
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> { await source.subscribe() }
}
private actor SessionTokens {
    var subscriptions = 0
    var continuation: AsyncThrowingStream<String, Error>.Continuation?
    func subscribe() -> AsyncThrowingStream<String, Error> {
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        continuation = pair.continuation; subscriptions += 1
        return pair.stream
    }
    func emit(_ text: String) { continuation?.yield(text) }
    func finish() { continuation?.finish() }
    func fail() { continuation?.finish(throwing: SessionTestError.failed) }
}
@MainActor private final class SessionAudio: VoiceConversationAudio {
    var isRecording = false
    var isFinishing = false
    var onTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?
    var onFinishing: (() -> Void)?
    var onError: ((String) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onPlaybackCancelled: (() -> Void)?
    var onInterruption: (() -> Void)?
    var starts = 0
    var spoken: [String] = []
    func startRecording() async throws { starts += 1; isRecording = true }
    func finishRecording() { isRecording = false; isFinishing = true; onFinishing?() }
    func stopRecording() { isRecording = false; isFinishing = false }
    func speak(_ text: String) throws { spoken.append(text) }
    func stopSpeaking() { }
}
