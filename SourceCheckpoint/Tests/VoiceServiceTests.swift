import XCTest
import AVFoundation
import Speech
@testable import JarvisEVO

/// Permission tests substitute OS authorization responses and a nil recognizer.
/// Playback tests substitute the synthesizer/session side effects, but invoke the
/// actual VoiceService delegate methods. No physical dictation/playback is claimed.
@MainActor
final class VoiceServiceTests: XCTestCase {
    func testAlreadyCancelledRecordingTaskDoesNotRequestPermission() async throws {
        var permissionRequests = 0
        let voice = VoiceService(permissions: VoicePermissions(requestSpeech: {
            permissionRequests += 1
            return .denied
        }, requestMicrophone: { false }))
        let attempt = Task { try await voice.startRecording() }
        attempt.cancel() // Do not yield before cancelling the queued operation.
        try await attempt.value
        XCTAssertEqual(permissionRequests, 0)
        XCTAssertFalse(voice.isStarting)
        XCTAssertFalse(voice.isRecording)
    }

    func testDeniedSpeechPermissionReturnsActionableErrorAndResetsStartingState() async throws {
        let voice = VoiceService(permissions: VoicePermissions(requestSpeech: { .denied }, requestMicrophone: { false }))
        await assertError(.speechPermission, from: voice)
        XCTAssertFalse(voice.isStarting)
        XCTAssertFalse(voice.isRecording)
        XCTAssertEqual(voice.transcript, "")
    }

    func testRestrictedSpeechPermissionDoesNotStartRecording() async throws {
        let voice = VoiceService(permissions: VoicePermissions(requestSpeech: { .restricted }, requestMicrophone: { false }))
        await assertError(.speechPermission, from: voice)
        XCTAssertFalse(voice.isStarting)
        XCTAssertFalse(voice.isRecording)
    }

    func testUndeterminedSpeechResponseDoesNotStartRecording() async throws {
        let voice = VoiceService(permissions: VoicePermissions(requestSpeech: { .notDetermined }, requestMicrophone: { false }))
        await assertError(.speechPermission, from: voice)
        XCTAssertFalse(voice.isStarting)
        XCTAssertFalse(voice.isRecording)
    }

    func testDeniedMicrophonePermissionReturnsItsOwnErrorWithoutStartingRecording() async throws {
        let voice = VoiceService(permissions: VoicePermissions(requestSpeech: { .authorized }, requestMicrophone: { false }))
        await assertError(.microphonePermission, from: voice)
        XCTAssertFalse(voice.isStarting)
        XCTAssertFalse(voice.isRecording)
    }

    func testMissingRecognizerReturnsUnavailableAfterGrantedSimulatedPermissions() async throws {
        let voice = VoiceService(permissions: VoicePermissions(requestSpeech: { .authorized }, requestMicrophone: { true }), recognizer: nil)
        await assertError(.unavailable, from: voice)
        XCTAssertFalse(voice.isStarting)
        XCTAssertFalse(voice.isRecording)
    }

    // An uncleared in-flight flag would make the second attempt return without an error.
    func testPermissionFailureCanBeRetried() async throws {
        let voice = VoiceService(permissions: VoicePermissions(requestSpeech: { .denied }, requestMicrophone: { false }))
        await assertError(.speechPermission, from: voice)
        await assertError(.speechPermission, from: voice)
        XCTAssertFalse(voice.isStarting)
    }

    // If the recordingID guard is removed, the late grant proceeds to microphone denial.
    func testStopDuringPermissionRequestIgnoresLateAuthorization() async throws {
        let pending = PendingSpeechPermission()
        let voice = waitingVoice(pending)
        defer { voice.stopRecording(); pending.resolveAll(.denied) }
        let attempt = Task { try await voice.startRecording() }
        try await waitFor { pending.count == 1 }
        XCTAssertTrue(voice.isStarting)
        voice.stopRecording()
        pending.resolveFirst(.authorized)
        try await attempt.value
        XCTAssertFalse(voice.isStarting)
        XCTAssertFalse(voice.isRecording)
    }

    func testRepeatedStartWhilePermissionIsPendingDoesNotOpenAnotherRequest() async throws {
        let pending = PendingSpeechPermission()
        let voice = waitingVoice(pending)
        defer { voice.stopRecording(); pending.resolveAll(.denied) }
        let first = Task { try await voice.startRecording() }
        try await waitFor { pending.count == 1 }
        var repeatedReturned = false
        let repeated = Task { try await voice.startRecording(); repeatedReturned = true }
        try await waitFor { repeatedReturned }
        try await repeated.value
        XCTAssertEqual(pending.count, 1)
        XCTAssertTrue(voice.isStarting)
        pending.resolveFirst(.denied)
        do { try await first.value; XCTFail("The original denial must still be reported") }
        catch { XCTAssertEqual((error as? VoiceError)?.errorDescription, VoiceError.speechPermission.errorDescription) }
    }

    // The second cancellation guard protects the await of the microphone permission too.
    func testStopDuringMicrophoneRequestIgnoresLateDenial() async throws {
        let pending = PendingMicrophonePermission()
        let voice = VoiceService(permissions: VoicePermissions(requestSpeech: { .authorized }, requestMicrophone: { await pending.request() }))
        defer { voice.stopRecording(); pending.resolve(false) }
        let attempt = Task { try await voice.startRecording() }
        try await waitFor { pending.isWaiting }
        voice.stopRecording()
        pending.resolve(false)
        try await attempt.value
        XCTAssertFalse(voice.isStarting)
        XCTAssertFalse(voice.isRecording)
    }

    // The old attempt's defer must not clear the new attempt's starting indicator.
    func testCancelledAttemptCannotClearStateOfNewPermissionRequest() async throws {
        let pending = PendingSpeechPermission()
        let voice = waitingVoice(pending)
        defer { voice.stopRecording(); pending.resolveAll(.denied) }
        let first = Task { try await voice.startRecording() }
        try await waitFor { pending.count == 1 }
        voice.stopRecording()
        let second = Task { try await voice.startRecording() }
        try await waitFor { pending.count == 2 }
        pending.resolveFirst(.authorized)
        try await first.value
        XCTAssertTrue(voice.isStarting)
        XCTAssertFalse(voice.isRecording)
        pending.resolveFirst(.denied)
        do { try await second.value; XCTFail("The current permission denial must be reported") }
        catch { XCTAssertEqual((error as? VoiceError)?.errorDescription, VoiceError.speechPermission.errorDescription) }
        XCTAssertFalse(voice.isStarting)
    }

    func testSyntheticInterruptionBeganCancelsPendingPermissionRequest() async throws {
        try await assertNotificationCancels(name: AVAudioSession.interruptionNotification,
                                            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
    }

    func testSyntheticOldDeviceUnavailableCancelsPendingPermissionRequest() async throws {
        try await assertNotificationCancels(name: AVAudioSession.routeChangeNotification,
                                            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
    }

    func testSyntheticMediaServicesResetCancelsPendingPermissionRequest() async throws {
        try await assertNotificationCancels(name: AVAudioSession.mediaServicesWereResetNotification, userInfo: nil)
    }

    // Treating interruption end as begin would silently discard the pending request.
    func testSyntheticInterruptionEndedDoesNotCancelPendingRequest() async throws {
        let pending = PendingSpeechPermission()
        let voice = waitingVoice(pending)
        defer { voice.stopRecording(); pending.resolveAll(.denied) }
        let attempt = Task { try await voice.startRecording() }
        try await waitFor { pending.count == 1 }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        pending.resolveFirst(.denied)
        do { try await attempt.value; XCTFail("Ending an interruption must not swallow a permission error") }
        catch { XCTAssertEqual((error as? VoiceError)?.errorDescription, VoiceError.speechPermission.errorDescription) }
        XCTAssertFalse(voice.isStarting)
    }

    // Removing the current utterance guard lets the cancelled first utterance
    // clear the second utterance's state and deactivate its audio session.
    func testLateCancelledUtteranceCannotStopReplacementPlayback() async throws {
        let boundary = ControlledSpeechPlayback()
        let session = TrackedVoiceSession()
        let voice = VoiceService(playback: boundary, audioSession: session.boundary)
        var completed = 0
        var cancelled = 0
        voice.onPlaybackFinished = { completed += 1 }
        voice.onPlaybackCancelled = { cancelled += 1 }
        try voice.speak("First response")
        let first = try XCTUnwrap(boundary.utterances.last)
        try voice.speak("Replacement response")
        let second = try XCTUnwrap(boundary.utterances.last)
        let deactivations = session.deactivations
        boundary.cancel(first)
        await drainVoiceCallbacks()
        XCTAssertTrue(voice.isSpeaking)
        XCTAssertEqual(session.deactivations, deactivations)
        XCTAssertEqual(cancelled, 0)
        boundary.finish(second)
        try await waitFor { !voice.isSpeaking }
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(session.deactivations, deactivations + 1)
    }

    func testLateFinishedUtteranceCannotFinishReplacementPlayback() async throws {
        let boundary = ControlledSpeechPlayback()
        let session = TrackedVoiceSession()
        let voice = VoiceService(playback: boundary, audioSession: session.boundary)
        var completed = 0
        voice.onPlaybackFinished = { completed += 1 }
        try voice.speak("First")
        let first = try XCTUnwrap(boundary.utterances.last)
        try voice.speak("Second")
        boundary.finish(first)
        await drainVoiceCallbacks()
        XCTAssertTrue(voice.isSpeaking)
        XCTAssertEqual(completed, 0)
        voice.stopSpeaking()
    }

    func testStoppedUtteranceCallbackCannotDeactivateNewPlayback() async throws {
        let boundary = ControlledSpeechPlayback()
        let session = TrackedVoiceSession()
        let voice = VoiceService(playback: boundary, audioSession: session.boundary)
        try voice.speak("Old")
        let old = try XCTUnwrap(boundary.utterances.last)
        voice.stopSpeaking()
        try voice.speak("New")
        let deactivations = session.deactivations
        boundary.finish(old)
        boundary.cancel(old)
        await drainVoiceCallbacks()
        XCTAssertTrue(voice.isSpeaking)
        XCTAssertEqual(session.deactivations, deactivations)
        voice.stopSpeaking()
    }

    func testCurrentCancellationStopsPlaybackAndNotifiesOnlyOnce() async throws {
        let boundary = ControlledSpeechPlayback()
        let session = TrackedVoiceSession()
        let voice = VoiceService(playback: boundary, audioSession: session.boundary)
        var cancelled = 0
        voice.onPlaybackCancelled = { cancelled += 1 }
        try voice.speak("Current")
        let utterance = try XCTUnwrap(boundary.utterances.last)
        let deactivations = session.deactivations
        boundary.cancel(utterance)
        try await waitFor { !voice.isSpeaking }
        boundary.finish(utterance)
        boundary.cancel(utterance)
        await drainVoiceCallbacks()
        XCTAssertEqual(cancelled, 1)
        XCTAssertEqual(session.deactivations, deactivations + 1)
    }

    func testLatePlaybackCallbackCannotDeactivatePendingRecordingPermission() async throws {
        let boundary = ControlledSpeechPlayback()
        let session = TrackedVoiceSession()
        let permission = PendingSpeechPermission()
        let voice = VoiceService(permissions: VoicePermissions(requestSpeech: { await permission.request() }, requestMicrophone: { false }),
                                 playback: boundary, audioSession: session.boundary)
        defer { voice.stopRecording(); permission.resolveAll(.denied) }
        try voice.speak("Before microphone")
        let utterance = try XCTUnwrap(boundary.utterances.last)
        let attempt = Task { try await voice.startRecording() }
        try await waitFor { permission.count == 1 }
        let deactivations = session.deactivations
        boundary.finish(utterance)
        boundary.cancel(utterance)
        await drainVoiceCallbacks()
        XCTAssertTrue(voice.isStarting)
        XCTAssertEqual(session.deactivations, deactivations)
        voice.stopRecording()
        permission.resolveFirst(.authorized)
        try await attempt.value
    }

    func testPlaybackActivationFailureDoesNotLeaveSpeakingState() throws {
        let boundary = ControlledSpeechPlayback()
        let session = TrackedVoiceSession()
        session.failActivation = true
        let voice = VoiceService(playback: boundary, audioSession: session.boundary)
        XCTAssertThrowsError(try voice.speak("Do not pretend this played"))
        XCTAssertFalse(voice.isSpeaking)
        XCTAssertTrue(boundary.utterances.isEmpty)
    }

    func testBlankPlaybackDoesNotStartAudioSession() throws {
        let boundary = ControlledSpeechPlayback()
        let session = TrackedVoiceSession()
        let voice = VoiceService(playback: boundary, audioSession: session.boundary)
        XCTAssertThrowsError(try voice.speak("  \n "))
        XCTAssertFalse(voice.isSpeaking)
        XCTAssertEqual(session.activations, 0)
    }

    func testEnergyDetectorEndsTurnOnlyAfterSpeechThenSustainedSilence() {
        var detector = VoiceActivityDetector()
        XCTAssertEqual(detector.observe(rms: 0, duration: 1), .listening)
        XCTAssertEqual(detector.observe(rms: 0.1, duration: 0.3), .listening)
        XCTAssertEqual(detector.observe(rms: 0, duration: 0.7), .listening)
        XCTAssertEqual(detector.observe(rms: 0.1, duration: 0.1), .listening)
        XCTAssertEqual(detector.observe(rms: 0, duration: 0.7), .listening)
        XCTAssertEqual(detector.observe(rms: 0, duration: 0.6), .endOfTurn)
    }

    func testEnergyDetectorRejectsClickAndBoundsEmptyOrContinuousInput() {
        var click = VoiceActivityDetector()
        XCTAssertEqual(click.observe(rms: 0.5, duration: 0.01), .listening)
        XCTAssertEqual(click.observe(rms: 0, duration: 1.5), .listening)
        XCTAssertEqual(click.observe(rms: 0, duration: 11), .noSpeech)
        var continuous = VoiceActivityDetector()
        XCTAssertEqual(continuous.observe(rms: 0.1, duration: 44), .listening)
        XCTAssertEqual(continuous.observe(rms: 0.1, duration: 1), .endOfTurn)
    }

    func testEnergyDetectorIgnoresInvalidSamples() {
        var detector = VoiceActivityDetector()
        XCTAssertEqual(detector.observe(rms: .nan, duration: 50), .listening)
        XCTAssertEqual(detector.observe(rms: 1, duration: -.infinity), .listening)
        XCTAssertEqual(detector.observe(rms: 0, duration: 1), .listening)
    }

    private func drainVoiceCallbacks() async {
        // AVSpeechSynthesizerDelegate bridges to MainActor in an unstructured task.
        // A short suspension drains those queued tasks without starting OS playback.
        try? await Task.sleep(for: .milliseconds(30))
    }

    func testSyntheticMediaResetRecreatesResourcesAndRetiresOldPlaybackIdentity() async throws {
        let resources = TrackedResetResources()
        let session = TrackedVoiceSession()
        let voice = VoiceService(audioSession: session.boundary, resources: resources.boundary)
        defer { voice.onInterruption = nil; voice.stopSpeaking() }
        try voice.speak("Before reset")
        let oldPlayback = try XCTUnwrap(resources.playbacks.first)
        let oldUtterance = try XCTUnwrap(oldPlayback.utterances.last)
        let retiredDelegate = try XCTUnwrap(oldPlayback.delegate)
        var notified = false
        voice.onInterruption = {
            XCTAssertEqual(resources.engineCreations, 2)
            XCTAssertEqual(resources.playbacks.count, 2)
            XCTAssertFalse(voice.isSpeaking)
            notified = true
        }
        let activations = session.activations
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        try await waitFor { notified }
        XCTAssertNil(oldPlayback.delegate)
        XCTAssertEqual(session.activations, activations, "Reset must not activate audio automatically")
        let newPlayback = try XCTUnwrap(resources.playbacks.last)
        XCTAssertFalse(newPlayback === oldPlayback)
        XCTAssertTrue(newPlayback.utterances.isEmpty)
        try voice.speak("Explicit restart")
        XCTAssertEqual(newPlayback.utterances.last?.speechString, "Explicit restart")
        retiredDelegate.speechSynthesizer?(AVSpeechSynthesizer(), didCancel: oldUtterance)
        await drainVoiceCallbacks()
        XCTAssertTrue(voice.isSpeaking)
        newPlayback.finish(try XCTUnwrap(newPlayback.utterances.last))
        try await waitFor { !voice.isSpeaking }
    }

    func testSyntheticMediaResetDoesNotResumePermissionAttemptOrStartAnotherOne() async throws {
        let pending = PendingSpeechPermission()
        let resources = TrackedResetResources()
        let voice = VoiceService(permissions: VoicePermissions(requestSpeech: { await pending.request() }, requestMicrophone: { false }),
                                 resources: resources.boundary)
        defer { voice.stopRecording(); pending.resolveAll(.denied) }
        let first = Task { try await voice.startRecording() }
        try await waitFor { pending.count == 1 }
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        try await waitFor { resources.engineCreations == 2 }
        XCTAssertFalse(voice.isStarting)
        XCTAssertEqual(pending.count, 1)
        pending.resolveFirst(.authorized)
        try await first.value
        XCTAssertFalse(voice.isRecording)
        let explicitRetry = Task { try await voice.startRecording() }
        try await waitFor { pending.count == 1 }
        voice.stopRecording()
        pending.resolveFirst(.denied)
        try await explicitRetry.value
    }

    func testIdleInterruptionAndHeadphoneRemovalDoNotReportFailedDictation() async {
        let session = TrackedVoiceSession()
        let voice = VoiceService(audioSession: session.boundary)
        var interruptions = 0
        voice.onInterruption = { interruptions += 1 }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        await drainVoiceCallbacks()
        XCTAssertEqual(interruptions, 0)
        XCTAssertFalse(voice.isRecording)
        XCTAssertFalse(voice.isSpeaking)
    }

    func testIdleMediaResetStillRecreatesResourcesWithoutFalseInterruption() async throws {
        let resources = TrackedResetResources()
        let session = TrackedVoiceSession()
        let voice = VoiceService(audioSession: session.boundary, resources: resources.boundary)
        var interruptions = 0
        voice.onInterruption = { interruptions += 1 }
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        try await waitFor { resources.engineCreations == 2 }
        XCTAssertEqual(interruptions, 0)
        XCTAssertEqual(resources.playbacks.count, 2)
        XCTAssertEqual(session.activations, 0)
    }

    private func waitingVoice(_ pending: PendingSpeechPermission) -> VoiceService {
        VoiceService(permissions: VoicePermissions(requestSpeech: { await pending.request() }, requestMicrophone: { false }))
    }

    private func assertNotificationCancels(name: Notification.Name, userInfo: [AnyHashable: Any]?) async throws {
        let pending = PendingSpeechPermission()
        let voice = waitingVoice(pending)
        defer { voice.stopRecording(); pending.resolveAll(.denied) }
        let attempt = Task { try await voice.startRecording() }
        try await waitFor { pending.count == 1 }
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        try await waitFor { !voice.isStarting }
        pending.resolveFirst(.authorized)
        try await attempt.value
        XCTAssertFalse(voice.isRecording)
        XCTAssertFalse(voice.isSpeaking)
    }

    private func assertError(_ expected: VoiceError, from voice: VoiceService, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await voice.startRecording(); XCTFail("Expected voice permission/availability failure", file: file, line: line) }
        catch {
            XCTAssertTrue(error is VoiceError, "Unexpected error: \(error)", file: file, line: line)
            XCTAssertEqual((error as? VoiceError)?.errorDescription, expected.errorDescription, file: file, line: line)
        }
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { XCTFail("Voice state did not settle"); throw VoiceWaitError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
private final class PendingSpeechPermission {
    private var pending: [CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>] = []
    var count: Int { pending.count }
    func request() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { pending.append($0) }
    }
    func resolveFirst(_ response: SFSpeechRecognizerAuthorizationStatus) { pending.removeFirst().resume(returning: response) }
    func resolveAll(_ response: SFSpeechRecognizerAuthorizationStatus) {
        let remaining = pending
        pending = []
        for continuation in remaining { continuation.resume(returning: response) }
    }
}

@MainActor
private final class PendingMicrophonePermission {
    private var pending: CheckedContinuation<Bool, Never>?
    var isWaiting: Bool { pending != nil }
    func request() async -> Bool { await withCheckedContinuation { pending = $0 } }
    func resolve(_ response: Bool) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: response)
    }
}

private enum VoiceWaitError: Error { case timeout }

/// Only synthesized playback and audio-session hardware effects are replaced.
/// Actual VoiceService delegate methods, identity guards and state run unchanged.
@MainActor
private final class ControlledSpeechPlayback: VoicePlayback {
    weak var delegate: (any AVSpeechSynthesizerDelegate)?
    private let source = AVSpeechSynthesizer()
    private(set) var utterances: [AVSpeechUtterance] = []
    func speak(_ utterance: AVSpeechUtterance) { utterances.append(utterance) }
    func stop() {}
    func finish(_ utterance: AVSpeechUtterance) { delegate?.speechSynthesizer?(source, didFinish: utterance) }
    func cancel(_ utterance: AVSpeechUtterance) { delegate?.speechSynthesizer?(source, didCancel: utterance) }
}

@MainActor
private final class TrackedVoiceSession {
    var activations = 0
    var deactivations = 0
    var failActivation = false
    var boundary: VoiceAudioSession {
        VoiceAudioSession(activateRecording: {}, activatePlayback: {
            self.activations += 1
            if self.failActivation { throw VoiceWaitError.timeout }
        }, deactivate: { self.deactivations += 1 })
    }
}

/// Factories observe real resource reconstruction, not a physical media reset.
/// Synthesized audio is controlled; the real AVAudioEngine is never started.
@MainActor
private final class TrackedResetResources {
    var engineCreations = 0
    var playbacks: [ControlledSpeechPlayback] = []
    var boundary: VoiceAudioResources {
        VoiceAudioResources(makeEngine: {
            self.engineCreations += 1
            return AVAudioEngine()
        }, makePlayback: {
            let playback = ControlledSpeechPlayback()
            self.playbacks.append(playback)
            return playback
        })
    }
}
