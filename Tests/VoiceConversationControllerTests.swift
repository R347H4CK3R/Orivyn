import XCTest
@testable import JarvisEVO

/// Controlled OS speech and provider completion boundaries exercise the real
/// controller. These tests do not claim microphone, audible output, or model QA.
@MainActor
final class VoiceConversationControllerTests: XCTestCase {
    func testFinalTranscriptAwaitsRealResponseThenPlaybackBeforeListeningAgain() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start(draft: "Please")
        try await waitFor { controller.state == .listening }
        audio.onTranscript?("explain gravity")
        XCTAssertEqual(controller.draft, "Please explain gravity")
        XCTAssertTrue(response.inputs.isEmpty)
        audio.onFinalTranscript?("explain gravity")
        try await waitFor { response.inputs.count == 1 }
        XCTAssertEqual(response.inputs, ["Please explain gravity"])
        XCTAssertEqual(controller.state, .awaitingResponse)
        XCTAssertTrue(audio.spoken.isEmpty)
        response.resolveFirst(.success("Gravity attracts mass."))
        try await waitFor { controller.state == .speaking }
        XCTAssertEqual(audio.spoken, ["Gravity attracts mass."])
        XCTAssertEqual(controller.draft, "")
        XCTAssertEqual(audio.starts, 1)
        audio.onPlaybackFinished?()
        try await waitFor { controller.state == .listening }
        XCTAssertEqual(audio.starts, 2)
        XCTAssertEqual(controller.transcript, "")
        controller.stop()
    }

    func testDuplicateFinalTranscriptSubmitsExactlyOneTurn() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { controller.state == .listening }
        audio.onFinalTranscript?("One turn")
        audio.onFinalTranscript?("One turn")
        try await waitFor { response.inputs.count == 1 }
        XCTAssertEqual(response.inputs, ["One turn"])
        controller.stop()
        response.resolveFirst(.success("Late response"))
        await drain()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(audio.spoken.isEmpty)
    }

    func testStopWhileAwaitingResponseCancelsAndIgnoresLateCompletion() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { controller.state == .listening }
        audio.onFinalTranscript?("Remember this transcription")
        try await waitFor { response.inputs.count == 1 }
        controller.stop()
        XCTAssertEqual(response.cancellations, 1)
        XCTAssertEqual(controller.draft, "Remember this transcription")
        response.resolveFirst(.success("Must never be spoken"))
        await drain()
        XCTAssertTrue(audio.spoken.isEmpty)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(audio.starts, 1)
    }

    func testPreviousProviderCompletionCannotSpeakDuringNewSessionResponse() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { controller.state == .listening }
        audio.onFinalTranscript?("Old question")
        try await waitFor { response.inputs.count == 1 }
        controller.stop()
        controller.start()
        try await waitFor { controller.state == .listening }
        audio.onFinalTranscript?("New question")
        try await waitFor { response.inputs.count == 2 }
        response.resolveFirst(.success("Old answer"))
        await drain()
        XCTAssertEqual(controller.state, .awaitingResponse)
        XCTAssertTrue(audio.spoken.isEmpty)
        response.resolveFirst(.success("New answer"))
        try await waitFor { controller.state == .speaking }
        XCTAssertEqual(audio.spoken, ["New answer"])
        controller.stop()
    }

    func testCallbacksFromPreviousSessionCannotSubmitOrRestartCurrentSession() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { controller.state == .listening }
        let oldFinal = audio.onFinalTranscript
        let oldError = audio.onError
        let oldFinish = audio.onPlaybackFinished
        controller.stop()
        controller.start(draft: "New")
        try await waitFor { controller.state == .listening }
        oldFinal?("Old transcript")
        oldError?("Old recognition error")
        oldFinish?()
        await drain()
        XCTAssertTrue(response.inputs.isEmpty)
        XCTAssertEqual(controller.state, .listening)
        XCTAssertEqual(controller.draft, "New")
        XCTAssertEqual(audio.starts, 2)
        controller.stop()
    }

    func testOldTurnCallbackCannotOverwriteNextTurnTranscript() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { controller.state == .listening }
        let oldPartial = audio.onTranscript
        let oldFinal = audio.onFinalTranscript
        audio.onFinalTranscript?("First")
        try await waitFor { response.inputs.count == 1 }
        response.resolveFirst(.success("Reply"))
        try await waitFor { controller.state == .speaking }
        audio.onPlaybackFinished?()
        try await waitFor { controller.state == .listening }
        audio.onTranscript?("Second")
        oldPartial?("Stale")
        oldFinal?("Stale")
        XCTAssertEqual(controller.draft, "Second")
        XCTAssertEqual(response.inputs.count, 1)
        controller.stop()
    }

    func testBackgroundStopsPendingPermissionAndNeverAutoResumes() async throws {
        let audio = ControlledConversationAudio()
        audio.holdStart = true
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { audio.pendingStart != nil }
        XCTAssertEqual(controller.state, .requestingPermission)
        controller.setForeground(false)
        audio.resolveStart()
        await drain()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isActive)
        controller.start()
        XCTAssertEqual(audio.starts, 1)
        controller.setForeground(true)
        XCTAssertEqual(audio.starts, 1)
    }

    func testRepeatedStartDuringPermissionRequestDoesNotCreateSecondRecording() async throws {
        let audio = ControlledConversationAudio()
        audio.holdStart = true
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { audio.pendingStart != nil }
        controller.start()
        XCTAssertEqual(audio.starts, 1)
        audio.resolveStart()
        try await waitFor { controller.state == .listening }
        controller.stop()
    }

    func testPermissionFailureIsActionableAndRetainsInitialDraft() async throws {
        let audio = ControlledConversationAudio()
        audio.startError = VoiceError.microphonePermission
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start(draft: "Existing draft")
        try await waitFor { controller.state == .failed }
        XCTAssertEqual(controller.errorMessage, VoiceError.microphonePermission.localizedDescription)
        XCTAssertEqual(controller.draft, "Existing draft")
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(response.inputs.isEmpty)
    }

    func testProviderFailureRetainsTranscriptAndDoesNotSpeakOrRestart() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { controller.state == .listening }
        audio.onFinalTranscript?("Keep my question")
        try await waitFor { response.inputs.count == 1 }
        response.resolveFirst(.failure(TestVoiceError.provider))
        try await waitFor { controller.state == .failed }
        XCTAssertEqual(controller.draft, "Keep my question")
        XCTAssertTrue(audio.spoken.isEmpty)
        XCTAssertEqual(audio.starts, 1)
    }

    func testEmptyResponseIsFailureNotSuccessfulPlayback() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { controller.state == .listening }
        audio.onFinalTranscript?("Question")
        try await waitFor { response.inputs.count == 1 }
        response.resolveFirst(.success(" \n "))
        try await waitFor { controller.state == .failed }
        XCTAssertTrue(audio.spoken.isEmpty)
        XCTAssertEqual(controller.draft, "Question")
    }

    func testFinishTurnWaitsForFinalResultRatherThanSendingPartialText() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { controller.state == .listening }
        audio.onTranscript?("Partial")
        controller.finishTurn()
        XCTAssertEqual(controller.state, .finishing)
        XCTAssertTrue(response.inputs.isEmpty)
        audio.onFinalTranscript?("Final corrected words")
        try await waitFor { response.inputs.count == 1 }
        XCTAssertEqual(response.inputs, ["Final corrected words"])
        controller.stop()
        response.resolveFirst(.success("Late"))
    }

    func testInterruptionCancelsVoiceWithoutAutomaticResume() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { controller.state == .listening }
        audio.onTranscript?("Interrupted draft")
        audio.onInterruption?()
        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(controller.draft, "Interrupted draft")
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(audio.starts, 1)
    }

    func testInterruptPlaybackStartsNewListenAndIgnoresCancelledOldPlayback() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { controller.state == .listening }
        audio.onFinalTranscript?("First")
        try await waitFor { response.inputs.count == 1 }
        response.resolveFirst(.success("Long response"))
        try await waitFor { controller.state == .speaking }
        let oldCancel = audio.onPlaybackCancelled
        let oldFinish = audio.onPlaybackFinished
        controller.interruptAndListen()
        try await waitFor { controller.state == .listening }
        oldCancel?()
        oldFinish?()
        XCTAssertEqual(controller.state, .listening)
        XCTAssertEqual(audio.starts, 2)
        controller.stop()
    }

    func testPlaybackFailureStopsInsteadOfRestartingMicrophone() async throws {
        let audio = ControlledConversationAudio()
        audio.playbackError = TestVoiceError.playback
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start()
        try await waitFor { controller.state == .listening }
        audio.onFinalTranscript?("Question")
        try await waitFor { response.inputs.count == 1 }
        response.resolveFirst(.success("Response"))
        try await waitFor { controller.state == .failed }
        XCTAssertEqual(audio.starts, 1)
        XCTAssertFalse(controller.isActive)
    }

    func testEmptyFinalDoesNotSendAnExistingDraftWithoutNewSpeech() async throws {
        let audio = ControlledConversationAudio()
        let response = PendingVoiceResponse()
        let controller = makeController(audio, response)
        controller.start(draft: "Existing unsent draft")
        try await waitFor { controller.state == .listening }
        audio.onFinalTranscript?(" \n ")
        XCTAssertEqual(controller.state, .failed)
        XCTAssertTrue(response.inputs.isEmpty)
        XCTAssertEqual(controller.draft, "Existing unsent draft")
    }

    private func makeController(_ audio: ControlledConversationAudio, _ response: PendingVoiceResponse) -> VoiceConversationController {
        VoiceConversationController(voice: audio, sendText: { try await response.send($0) }, cancelResponse: { response.cancellations += 1 })
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { XCTFail("Voice conversation did not settle"); throw TestVoiceError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private func drain() async { try? await Task.sleep(for: .milliseconds(30)) }
}

@MainActor
private final class ControlledConversationAudio: VoiceConversationAudio {
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
    var holdStart = false
    var pendingStart: CheckedContinuation<Void, Never>?
    var startError: (any Error)?
    var playbackError: (any Error)?
    private var startID: UUID?
    func startRecording() async throws {
        starts += 1
        let id = UUID()
        startID = id
        if let startError { throw startError }
        if holdStart { await withCheckedContinuation { pendingStart = $0 } }
        guard startID == id else { return }
        isRecording = true
    }
    func resolveStart() { let pending = pendingStart; pendingStart = nil; pending?.resume() }
    func stopRecording() { startID = nil; isRecording = false; isFinishing = false }
    func finishRecording() { isRecording = false; isFinishing = true; onFinishing?() }
    func speak(_ text: String) throws { if let playbackError { throw playbackError }; spoken.append(text) }
    func stopSpeaking() {}
}

@MainActor
private final class PendingVoiceResponse {
    var inputs: [String] = []
    var cancellations = 0
    private var pending: [CheckedContinuation<String, any Error>] = []
    func send(_ text: String) async throws -> String {
        inputs.append(text)
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func resolveFirst(_ result: Result<String, any Error>) { pending.removeFirst().resume(with: result) }
}

private enum TestVoiceError: Error { case provider, playback, timeout }
