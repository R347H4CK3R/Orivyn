import Foundation
import Observation

/// VoiceService is the production implementation. Substituting this boundary in
/// controller tests does not replace the controller's lifecycle/state machine.
@MainActor
protocol VoiceConversationAudio: AnyObject {
    var isRecording: Bool { get }
    var isFinishing: Bool { get }
    var onTranscript: ((String) -> Void)? { get set }
    var onFinalTranscript: ((String) -> Void)? { get set }
    var onFinishing: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onPlaybackFinished: (() -> Void)? { get set }
    var onPlaybackCancelled: (() -> Void)? { get set }
    var onInterruption: (() -> Void)? { get set }
    func startRecording() async throws
    func finishRecording()
    func stopRecording()
    func speak(_ text: String) throws
    func stopSpeaking()
}

/// One foreground-only loop: final on-device transcript -> real provider result
/// -> TTS completion -> next listen. Never sends a partial transcript or speaks
/// streaming/failed model output. No background microphone or wake-word service.
///
/// Integration contract:
/// - sendText must persist/send the supplied text and await THAT response's full,
///   successful completion. Returning immediately after AppModel.send() is wrong.
/// - cancelResponse must cancel only the generation owned by this voice turn.
/// - onDraftChanged updates the composer; do not allow simultaneous dictation or
///   editing while active. Accepted turns belong in normal conversation history.
/// - setForeground(false) on scenePhase == .background, NOT .inactive. Permission
///   prompts temporarily make the scene inactive and must not cancel themselves.
/// - stop before changing conversation/provider, and before manual dictation or
///   unrelated read-aloud. Foreground return never starts the microphone itself.
@MainActor @Observable
final class VoiceConversationController {
    enum State: Equatable {
        case idle, requestingPermission, listening, finishing, awaitingResponse, speaking, failed
    }

    private(set) var state: State = .idle
    private(set) var draft = ""
    private(set) var transcript = ""
    private(set) var errorMessage: String?
    private(set) var isForeground = true
    var onDraftChanged: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let voice: any VoiceConversationAudio
    private let sendText: @MainActor (String) async throws -> String
    private let cancelResponse: @MainActor () -> Void
    private var operation: Task<Void, Never>?
    private var sessionID: UUID?
    private var turnID: UUID?
    private var prefix = ""

    init(voice: any VoiceConversationAudio,
         sendText: @escaping @MainActor (String) async throws -> String,
         cancelResponse: @escaping @MainActor () -> Void) {
        self.voice = voice
        self.sendText = sendText
        self.cancelResponse = cancelResponse
    }

    var isActive: Bool { sessionID != nil }

    /// Explicit user start only. Existing composer text is retained as the first
    /// turn's prefix, but is never sent if recognition returns no new speech.
    func start(draft: String = "") {
        guard isForeground, !isActive else { return }
        self.draft = draft
        errorMessage = nil
        let session = UUID()
        sessionID = session
        beginListening(session: session, prefix: draft)
    }

    /// Stops the microphone, queued synthesis and this turn's generation. Keeps
    /// an unfinished transcript for review; an old callback cannot resume a loop.
    func stop() {
        let wasAwaiting = state == .awaitingResponse
        sessionID = nil
        turnID = nil
        operation?.cancel()
        operation = nil
        clearVoiceCallbacks()
        voice.stopRecording()
        voice.stopSpeaking()
        if wasAwaiting { cancelResponse() }
        state = .idle
    }

    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        if !foreground { stop() }
    }

    /// Explicit end-of-turn control still waits for a genuine final transcript.
    func finishTurn() {
        guard isActive, state == .listening else { return }
        state = .finishing
        voice.finishRecording()
    }

    /// Push-to-interrupt. This is not acoustic barge-in: the microphone stays off
    /// while the app speaks, avoiding capture of its own synthesized response.
    func interruptAndListen() {
        guard isForeground, let session = sessionID,
              state == .speaking || state == .awaitingResponse else { return }
        let wasAwaiting = state == .awaitingResponse
        turnID = nil
        operation?.cancel()
        operation = nil
        clearVoiceCallbacks()
        voice.stopRecording()
        voice.stopSpeaking()
        if wasAwaiting { cancelResponse() }
        draft = ""
        onDraftChanged?(draft)
        beginListening(session: session, prefix: "")
    }

    private func beginListening(session: UUID, prefix: String) {
        guard sessionID == session, isForeground else { return }
        let turn = UUID()
        turnID = turn
        self.prefix = prefix
        transcript = ""
        state = .requestingPermission
        installVoiceCallbacks(session: session, turn: turn)
        operation = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.matches(session, turn),
                  self.state == .requestingPermission else { return }
            do {
                try await self.voice.startRecording()
                guard !Task.isCancelled, self.matches(session, turn) else { return }
                // A final callback is allowed to arrive before start returns.
                guard self.state == .requestingPermission else { return }
                if self.voice.isRecording { self.state = .listening }
                else if self.voice.isFinishing { self.state = .finishing }
                else { self.fail(VoiceConversationError.interrupted.localizedDescription) }
            } catch {
                guard !Task.isCancelled, self.matches(session, turn) else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    private func installVoiceCallbacks(session: UUID, turn: UUID) {
        voice.onTranscript = { [weak self] text in
            guard let self, self.matches(session, turn), self.acceptsTranscript else { return }
            self.updateTranscript(text)
        }
        voice.onFinalTranscript = { [weak self] text in
            guard let self, self.matches(session, turn), self.acceptsTranscript else { return }
            self.submitFinal(text, session: session, turn: turn)
        }
        voice.onFinishing = { [weak self] in
            guard let self, self.matches(session, turn), self.acceptsTranscript else { return }
            self.state = .finishing
        }
        voice.onError = { [weak self] message in
            guard let self, self.matches(session, turn) else { return }
            self.fail(message)
        }
        voice.onInterruption = { [weak self] in
            guard let self, self.matches(session, turn) else { return }
            self.fail(VoiceConversationError.interrupted.localizedDescription)
        }
        voice.onPlaybackFinished = { [weak self] in
            guard let self, self.matches(session, turn), self.state == .speaking else { return }
            self.beginListening(session: session, prefix: "")
        }
        voice.onPlaybackCancelled = { [weak self] in
            guard let self, self.matches(session, turn), self.state == .speaking else { return }
            self.fail(VoiceConversationError.interrupted.localizedDescription)
        }
    }

    private var acceptsTranscript: Bool {
        state == .requestingPermission || state == .listening || state == .finishing
    }

    private func updateTranscript(_ text: String) {
        transcript = text
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = trimmedPrefix.isEmpty ? text : trimmedPrefix + (text.isEmpty ? "" : " " + text)
        onDraftChanged?(draft)
    }

    private func submitFinal(_ text: String, session: UUID, turn: UUID) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail(VoiceError.noSpeech.localizedDescription)
            return
        }
        updateTranscript(text)
        guard matches(session, turn), acceptsTranscript else { return }
        let submitted = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        voice.stopRecording()
        operation?.cancel()
        state = .awaitingResponse
        operation = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.matches(session, turn),
                  self.state == .awaitingResponse else { return }
            do {
                let response = try await self.sendText(submitted)
                guard !Task.isCancelled, self.matches(session, turn), self.state == .awaitingResponse else { return }
                guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw VoiceConversationError.emptyResponse
                }
                self.draft = ""
                self.onDraftChanged?("")
                guard !Task.isCancelled, self.matches(session, turn), self.state == .awaitingResponse else { return }
                self.state = .speaking
                try self.voice.speak(response)
            } catch {
                guard !Task.isCancelled, self.matches(session, turn) else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    private func matches(_ session: UUID, _ turn: UUID) -> Bool {
        sessionID == session && turnID == turn && isForeground
    }

    private func fail(_ message: String) {
        stop()
        errorMessage = message
        state = .failed
        onError?(message)
    }

    private func clearVoiceCallbacks() {
        voice.onTranscript = nil
        voice.onFinalTranscript = nil
        voice.onFinishing = nil
        voice.onError = nil
        voice.onPlaybackFinished = nil
        voice.onPlaybackCancelled = nil
        voice.onInterruption = nil
    }
}

private enum VoiceConversationError: LocalizedError {
    case interrupted, emptyResponse
    var errorDescription: String? {
        switch self {
        case .interrupted: return "Voice conversation was interrupted. Tap Voice to resume when you’re ready."
        case .emptyResponse: return "The model returned no response. Voice conversation has stopped; you can retry your message."
        }
    }
}
