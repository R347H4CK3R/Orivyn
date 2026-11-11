import XCTest
import AVFoundation
import Speech
@testable import JarvisEVO

/// These tests substitute only OS permission responses and, for availability, a
/// nil recognizer. They exercise VoiceService state and real notification handlers.
/// They never start microphone capture or claim physical dictation/playback coverage.
@MainActor
final class VoiceServiceTests: XCTestCase {
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
