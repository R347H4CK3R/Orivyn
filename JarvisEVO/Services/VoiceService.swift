import AVFoundation
import Observation
import Speech
import Synchronization

@MainActor @Observable
final class VoiceService: NSObject, VoiceConversationAudio {
    private(set) var isRecording = false
    private(set) var isStarting = false
    private(set) var isFinishing = false
    private var recordingID: UUID?
    private(set) var isSpeaking = false
    private(set) var transcript = ""
    private(set) var inputLevel: Float = 0
    private let recognizer: SFSpeechRecognizer?
    private let permissions: VoicePermissions
    private var engine: AVAudioEngine
    private var playback: any VoicePlayback
    private let resources: VoiceAudioResources
    private let audioSession: VoiceAudioSession
    private var currentUtterance: AVSpeechUtterance?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var activityTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var hasInputTap = false
    var onTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?
    var onFinishing: (() -> Void)?
    var onError: ((String) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onPlaybackCancelled: (() -> Void)?
    var onInterruption: (() -> Void)?

    init(permissions: VoicePermissions = .system, recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(),
         playback: (any VoicePlayback)? = nil, audioSession: VoiceAudioSession = .system,
         resources: VoiceAudioResources = .system) {
        self.permissions = permissions
        self.recognizer = recognizer
        self.resources = resources
        self.engine = resources.makeEngine()
        self.playback = playback ?? resources.makePlayback()
        self.audioSession = audioSession
        super.init()
        self.playback.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioServicesReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc nonisolated private func audioInterrupted(_ notification: Notification) {
        let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
        Task { @MainActor [weak self] in self?.handleInterruption() }
    }

    @objc nonisolated private func audioRouteChanged(_ notification: Notification) {
        let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
        Task { @MainActor [weak self] in self?.handleInterruption() }
    }

    @objc nonisolated private func audioServicesReset(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.handleMediaServicesReset() }
    }

    private func handleMediaServicesReset() {
        let wasActive = isRecording || isStarting || isFinishing || isSpeaking
        // QA1749: orphaned media objects must be recreated, not merely stopped.
        // Retire IDs before disposal so queued old delegates cannot affect retry.
        stopRecording()
        stopSpeaking()
        playback.delegate = nil
        engine = resources.makeEngine()
        playback = resources.makePlayback()
        playback.delegate = self
        // Session category/mode are reapplied only on an explicit subsequent
        // start/speak. Rebuilding resources never activates capture or playback.
        if wasActive { onInterruption?() }
    }

    private func handleInterruption() {
        let wasActive = isRecording || isStarting || isFinishing || isSpeaking
        stopRecording()
        stopSpeaking()
        if wasActive { onInterruption?() }
    }

    func startRecording() async throws {
        guard !Task.isCancelled, !isRecording && !isStarting && !isFinishing else { return }
        let attempt = UUID()
        recordingID = attempt
        isStarting = true
        defer {
            if recordingID == attempt {
                isStarting = false
                if !isRecording && !isFinishing { recordingID = nil; deactivateSessionIfIdle() }
            }
        }
        stopSpeaking()
        let authorization = await permissions.requestSpeech()
        guard recordingID == attempt, !Task.isCancelled else { return }
        guard authorization == .authorized else { throw VoiceError.speechPermission }
        let microphone = await permissions.requestMicrophone()
        guard recordingID == attempt, !Task.isCancelled else { return }
        guard microphone else { throw VoiceError.microphonePermission }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw VoiceError.unavailable }
        try audioSession.activateRecording()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        transcript = ""
        inputLevel = 0
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { stopRecording(); throw VoiceError.unavailable }
        let audioSink = RecognitionAudioSink(request: request)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in audioSink.append(buffer) }
        hasInputTap = true
        recognitionTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.recordingID == attempt else { return }
                if let text { self.transcript = text; self.onTranscript?(text) }
                guard self.recordingID == attempt else { return }
                if final {
                    let finalText = self.transcript
                    self.stopRecording()
                    self.onFinalTranscript?(finalText)
                } else if let message {
                    self.stopRecording()
                    self.onError?(message)
                }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            monitorActivity(audioSink, attempt: attempt)
        } catch {
            stopRecording()
            throw error
        }
    }

    /// Ends input but waits for the recognizer's actual final result. Stopping or
    /// switching conversations uses stopRecording instead and discards late results.
    func finishRecording() {
        guard isRecording, let attempt = recordingID else { return }
        isRecording = false
        isFinishing = true
        stopAudioInput()
        request?.endAudio()
        onFinishing?()
        guard recordingID == attempt else { return }
        finalizationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard let self, self.recordingID == attempt, self.isFinishing else { return }
            self.stopRecording()
            self.onError?(VoiceError.finalizationTimeout.localizedDescription)
        }
    }

    func stopRecording() {
        recordingID = nil
        isStarting = false
        isRecording = false
        isFinishing = false
        stopAudioInput()
        finalizationTask?.cancel()
        finalizationTask = nil
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        deactivateSessionIfIdle()
    }

    private func stopAudioInput() {
        activityTask?.cancel()
        activityTask = nil
        engine.stop()
        if hasInputTap { engine.inputNode.removeTap(onBus: 0); hasInputTap = false }
        inputLevel = 0
    }

    private func monitorActivity(_ sink: RecognitionAudioSink, attempt: UUID) {
        let deadline = ContinuousClock.now + .seconds(45)
        activityTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.recordingID == attempt, self.isRecording else { return }
                self.inputLevel = sink.level
                // Also bound wall time if the OS stops delivering audio buffers.
                if ContinuousClock.now >= deadline { self.finishRecording(); return }
                switch sink.decision {
                case .listening: break
                case .endOfTurn: self.finishRecording(); return
                case .noSpeech:
                    self.stopRecording()
                    self.onError?(VoiceError.noSpeech.localizedDescription)
                    return
                }
            }
        }
    }

    func speak(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VoiceError.emptyPlayback }
        stopRecording()
        // Invalidate before stopping: the old cancellation may arrive after the
        // replacement utterance has started playing.
        currentUtterance = nil
        isSpeaking = false
        playback.stop()
        do { try audioSession.activatePlayback() }
        catch { deactivateSessionIfIdle(); throw error }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        currentUtterance = utterance
        isSpeaking = true
        playback.speak(utterance)
    }

    func stopSpeaking() {
        currentUtterance = nil
        isSpeaking = false
        playback.stop()
        deactivateSessionIfIdle()
    }

    private func completePlayback(identity: ObjectIdentifier, finished: Bool) {
        guard let currentUtterance, ObjectIdentifier(currentUtterance) == identity else { return }
        self.currentUtterance = nil
        isSpeaking = false
        deactivateSessionIfIdle()
        if finished { onPlaybackFinished?() } else { onPlaybackCancelled?() }
    }

    private func deactivateSessionIfIdle() {
        guard !isRecording && !isStarting && !isFinishing && !isSpeaking else { return }
        audioSession.deactivate()
    }
}

extension VoiceService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = RetainedUtteranceIdentity(utterance)
        Task { @MainActor [weak self] in self?.completePlayback(identity: identity.id, finished: true) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identity = RetainedUtteranceIdentity(utterance)
        Task { @MainActor [weak self] in self?.completePlayback(identity: identity.id, finished: false) }
    }
}

/// Retains identity until the delegate task runs, preventing pointer reuse. No
/// utterance properties are read or mutated across the concurrency boundary.
private final class RetainedUtteranceIdentity: @unchecked Sendable {
    private let utterance: AVSpeechUtterance
    var id: ObjectIdentifier { ObjectIdentifier(utterance) }
    init(_ utterance: AVSpeechUtterance) { self.utterance = utterance }
}

/// Bounded energy-based endpoint detection, not speaker or semantic detection.
/// Silence is measured from audio duration, not recognition callback arrival time.
struct VoiceActivityDetector {
    enum Decision: UInt8 { case listening, endOfTurn, noSpeech }
    private var elapsed: TimeInterval = 0
    private var voiced: TimeInterval = 0
    private var silence: TimeInterval = 0
    private var terminal: Decision?

    mutating func observe(rms: Float, duration: TimeInterval) -> Decision {
        if let terminal { return terminal }
        guard rms.isFinite, rms >= 0, duration.isFinite, duration > 0 else { return .listening }
        elapsed += duration
        if rms >= 0.015 { voiced += duration; silence = 0 }
        else { silence += duration }
        if voiced >= 0.2 && (silence >= 1.2 || elapsed >= 45) { terminal = .endOfTurn }
        else if elapsed >= 12 && voiced < 0.2 { terminal = .noSpeech }
        return terminal ?? .listening
    }
}

/// Only the serial input tap mutates the detector. MainActor polls lock-free
/// atomic snapshots. The tap allocates no tasks, acquires no locks, reads at most
/// 1,024 samples, and never accesses UI/actor state. The OS append is unavoidable.
private final class RecognitionAudioSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private var detector = VoiceActivityDetector()
    private let levelBits = Atomic<UInt32>(0)
    private let decisionValue = Atomic<UInt8>(0)
    var level: Float { Float(bitPattern: levelBits.load(ordering: .relaxed)) }
    var decision: VoiceActivityDetector.Decision {
        VoiceActivityDetector.Decision(rawValue: decisionValue.load(ordering: .relaxed)) ?? .listening
    }
    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
        let frames = Int(buffer.frameLength)
        guard frames > 0, buffer.format.sampleRate > 0, let samples = buffer.floatChannelData?[0] else { return }
        let step = max(1, (frames + 1023) / 1024)
        var squares: Float = 0
        var count = 0
        for frame in stride(from: 0, to: frames, by: step) {
            let value = samples[frame]
            squares += value * value
            count += 1
        }
        let rms = (squares / Float(count)).squareRoot()
        let decision = detector.observe(rms: rms, duration: Double(frames) / buffer.format.sampleRate)
        let level: Float = rms.isFinite ? min(1, max(0, rms * 5)) : 0
        levelBits.store(level.bitPattern, ordering: .relaxed)
        decisionValue.store(decision.rawValue, ordering: .relaxed)
    }
}

@MainActor
protocol VoicePlayback: AnyObject {
    var delegate: (any AVSpeechSynthesizerDelegate)? { get set }
    func speak(_ utterance: AVSpeechUtterance)
    func stop()
}

/// Real OS resources by default. Factories permit deterministic reset-boundary
/// tests without pretending a synthetic notification invalidates audio hardware.
@MainActor
struct VoiceAudioResources {
    var makeEngine: @MainActor () -> AVAudioEngine
    var makePlayback: @MainActor () -> any VoicePlayback
    static let system = VoiceAudioResources(makeEngine: { AVAudioEngine() }, makePlayback: { SystemVoicePlayback() })
}

@MainActor
private final class SystemVoicePlayback: VoicePlayback {
    private let synthesizer = AVSpeechSynthesizer()
    var delegate: (any AVSpeechSynthesizerDelegate)? {
        get { synthesizer.delegate }
        set { synthesizer.delegate = newValue }
    }
    func speak(_ utterance: AVSpeechUtterance) { synthesizer.speak(utterance) }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

/// Only audio-session side effects are replaced by state tests. The shipped
/// default always configures and activates the real AVAudioSession.
@MainActor
struct VoiceAudioSession {
    var activateRecording: @MainActor () throws -> Void
    var activatePlayback: @MainActor () throws -> Void
    var deactivate: @MainActor () -> Void
    static let system = VoiceAudioSession(
        activateRecording: {
            let session = AVAudioSession.sharedInstance()
            // Apple's Speech tutorial uses playAndRecord/measurement. Avoid
            // prolonged ducking during up-to-45-second listening turns.
            try session.setCategory(.playAndRecord, mode: .measurement, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        },
        activatePlayback: {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try session.setActive(true)
        },
        deactivate: { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    )
}

/// OS permission requests are the only substituted boundary in permission tests.
/// The app's default always invokes the real system dialogs and authorization APIs.
@MainActor
struct VoicePermissions {
    var requestSpeech: @MainActor () async -> SFSpeechRecognizerAuthorizationStatus
    var requestMicrophone: @MainActor () async -> Bool

    static let system = VoicePermissions(
        requestSpeech: {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
            }
        },
        requestMicrophone: { await AVAudioApplication.requestRecordPermission() }
    )
}
