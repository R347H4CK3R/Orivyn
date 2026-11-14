import Foundation

// Explicit audio/provider boundary doubles; the production controller is unchanged.
@MainActor final class ControlledAudio: VoiceConversationAudio {
    var isRecording = false, isFinishing = false
    var onTranscript: ((String) -> Void)?, onFinalTranscript: ((String) -> Void)?
    var onFinishing: (() -> Void)?, onError: ((String) -> Void)?
    var onPlaybackFinished: (() -> Void)?, onPlaybackCancelled: (() -> Void)?, onInterruption: (() -> Void)?
    var starts = 0, finishes = 0, stops = 0, playbackStops = 0
    var spoken: [String] = []
    func startRecording() async throws { starts += 1; isRecording = true }
    func finishRecording() { finishes += 1; isFinishing = true; isRecording = false; onFinishing?() }
    func stopRecording() { stops += 1; isRecording = false; isFinishing = false }
    func speak(_ text: String) throws { spoken.append(text) }
    func stopSpeaking() { playbackStops += 1 }
}
@MainActor final class ControlledResponse {
    var inputs: [String] = [], pending: [CheckedContinuation<String, any Error>] = []
    var cancellations = 0
    func send(_ text: String) async throws -> String {
        inputs.append(text)
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func finish(_ result: Result<String, any Error>) throws {
        guard !pending.isEmpty else { throw SmokeFailure(message: "No pending response to finish") }
        pending.removeFirst().resume(with: result)
    }
}
struct SmokeFailure: Error { let message: String }
@main struct VoiceSmoke {
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SmokeFailure(message: message) }
    }
    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 { if predicate() { return }; try await Task.sleep(for: .milliseconds(1)) }
        throw SmokeFailure(message: "Bounded wait timed out")
    }
    @MainActor static func drain() async throws {
        for _ in 0..<30 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(2))
    }
    @MainActor static func make(_ audio: ControlledAudio, _ response: ControlledResponse) -> VoiceConversationController {
        VoiceConversationController(voice: audio, sendText: { try await response.send($0) }, cancelResponse: { response.cancellations += 1 })
    }
    @MainActor static func main() async throws {
        try await stopBeforeEntry()
        try await finalOnlyAndCompletePlayback()
        try await stopBeforeSendEntry()
        try await staleCallbacksAndResponse()
        try await backgroundStop()
        try await failedResponseNeverPlays()
        try await emptyFinalNeverSends()
        print("PASS: 7 production-controller lifecycle scenarios; controlled audio/provider only. No microphone, TTS, model, Apple API or iPhone verification.")
    }
    @MainActor static func stopBeforeEntry() async throws {
        let a = ControlledAudio(), r = ControlledResponse(), c: VoiceConversationController
        c = make(a,r); c.start(); c.stop(); try await drain()
        try check(a.starts == 0 && !a.isRecording && c.state == .idle && !c.isActive, "Stop before task entry must prevent audio start")
        print("PASS stop-before-listen-task-entry")
    }
    @MainActor static func finalOnlyAndCompletePlayback() async throws {
        let a = ControlledAudio(), r = ControlledResponse(), c: VoiceConversationController
        c = make(a,r); c.start(draft: "Please"); try await wait { c.state == .listening }
        let final = a.onFinalTranscript
        a.onTranscript?("explain gravity"); try check(r.inputs.isEmpty && a.spoken.isEmpty, "Partial transcript must not submit/play")
        c.finishTurn(); try check(c.state == .finishing && r.inputs.isEmpty, "Finishing must await final")
        final?("explain gravity"); final?("duplicate final"); try await wait { r.inputs.count == 1 }
        try check(r.inputs == ["Please explain gravity"] && c.state == .awaitingResponse && a.spoken.isEmpty, "Exactly one finalized prefixed turn; no precompletion playback")
        try r.finish(.success("Gravity attracts mass.")); try await wait { c.state == .speaking }
        try check(a.spoken == ["Gravity attracts mass."] && a.starts == 1 && c.draft.isEmpty, "Only full completed response speaks")
        a.onPlaybackFinished?(); try await wait { c.state == .listening }
        try check(a.starts == 2 && c.transcript.isEmpty, "Listen again only after playback completion")
        c.stop(); print("PASS final-only-duplicate-final-complete-response-playback")
    }
    @MainActor static func stopBeforeSendEntry() async throws {
        let a = ControlledAudio(), r = ControlledResponse(), c: VoiceConversationController
        c = make(a,r); c.start(); try await wait { c.state == .listening }
        a.onFinalTranscript?("Do not send"); c.stop(); try await drain()
        try check(r.inputs.isEmpty && a.spoken.isEmpty && c.state == .idle, "Stop before response task entry must suppress send")
        print("PASS stop-before-response-task-entry")
    }
    @MainActor static func staleCallbacksAndResponse() async throws {
        let a = ControlledAudio(), r = ControlledResponse(), c: VoiceConversationController
        c = make(a,r); c.start(); try await wait { c.state == .listening }
        let oldFinal = a.onFinalTranscript, oldPartial = a.onTranscript, oldPlayback = a.onPlaybackFinished, oldError = a.onError
        oldFinal?("old turn"); try await wait { r.inputs.count == 1 }; c.stop(); c.start(draft: "New"); try await wait { c.state == .listening }
        oldPartial?("stale partial"); oldFinal?("stale final"); oldPlayback?(); oldError?("stale error")
        try r.finish(.success("Stale answer")); try await drain()
        try check(r.inputs == ["old turn"] && a.spoken.isEmpty && c.draft == "New" && c.state == .listening && a.starts == 2, "Old callbacks/results must not affect restarted session")
        try check(r.cancellations == 1, "Only owned pending response cancelled")
        c.stop(); print("PASS stale-callbacks-response-after-stop-restart")
    }
    @MainActor static func backgroundStop() async throws {
        let a = ControlledAudio(), r = ControlledResponse(), c: VoiceConversationController
        c = make(a,r); c.start(); try await wait { c.state == .listening }
        a.onFinalTranscript?("pending"); try await wait { r.inputs.count == 1 }
        c.setForeground(false); try r.finish(.success("Background result")); try await drain()
        try check(!c.isActive && !a.isRecording && c.state == .idle && a.spoken.isEmpty && r.cancellations == 1, "Background must stop all owned work")
        c.start(); try await drain(); try check(a.starts == 1, "Background explicit start blocked")
        c.setForeground(true); try await drain(); try check(a.starts == 1 && !c.isActive, "Foreground must not restart microphone")
        print("PASS background-stop-no-automatic-resume")
    }
    @MainActor static func failedResponseNeverPlays() async throws {
        let a = ControlledAudio(), r = ControlledResponse(), c: VoiceConversationController
        c = make(a,r); c.start(); try await wait { c.state == .listening }; a.onFinalTranscript?("question"); try await wait { r.inputs.count == 1 }
        try r.finish(.failure(SmokeFailure(message:"Controlled provider failure"))); try await wait { c.state == .failed }
        try check(a.spoken.isEmpty && !c.isActive && c.errorMessage != nil, "Failed response must not play")
        c.stop(); print("PASS failed-response-no-playback")
    }
    @MainActor static func emptyFinalNeverSends() async throws {
        let a = ControlledAudio(), r = ControlledResponse(), c: VoiceConversationController
        c = make(a,r); c.start(draft:"Keep draft"); try await wait { c.state == .listening }; a.onFinalTranscript?(" \n "); try await drain()
        try check(c.state == .failed && r.inputs.isEmpty && a.spoken.isEmpty && c.errorMessage == VoiceError.noSpeech.localizedDescription, "Empty speech must not send draft")
        c.stop(); print("PASS empty-final-no-submission")
    }
}
