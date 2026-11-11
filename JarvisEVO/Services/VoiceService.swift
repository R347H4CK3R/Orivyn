import AVFoundation
import Observation
import Speech

@MainActor @Observable
final class VoiceService: NSObject {
    private(set) var isRecording = false
    private(set) var isStarting = false
    private var recordingID: UUID?
    private(set) var isSpeaking = false
    private(set) var transcript = ""
    private let recognizer: SFSpeechRecognizer?
    private let permissions: VoicePermissions
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInputTap = false
    var onTranscript: ((String) -> Void)?
    var onError: ((String) -> Void)?

    init(permissions: VoicePermissions = .system, recognizer: SFSpeechRecognizer? = SFSpeechRecognizer()) {
        self.permissions = permissions
        self.recognizer = recognizer
        super.init()
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioServicesReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc nonisolated private func audioInterrupted(_ notification: Notification) {
        let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
        Task { @MainActor [weak self] in self?.stopRecording(); self?.stopSpeaking() }
    }

    @objc nonisolated private func audioRouteChanged(_ notification: Notification) {
        let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
        Task { @MainActor [weak self] in self?.stopRecording(); self?.stopSpeaking() }
    }

    @objc nonisolated private func audioServicesReset(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.stopRecording(); self?.stopSpeaking() }
    }

    func startRecording() async throws {
        guard !isRecording && !isStarting else { return }
        let attempt = UUID()
        recordingID = attempt
        isStarting = true
        defer { if recordingID == attempt { isStarting = false } }
        stopSpeaking()
        let authorization = await permissions.requestSpeech()
        guard recordingID == attempt else { return }
        guard authorization == .authorized else { throw VoiceError.speechPermission }
        let microphone = await permissions.requestMicrophone()
        guard recordingID == attempt else { return }
        guard microphone else { throw VoiceError.microphonePermission }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw VoiceError.unavailable }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        transcript = ""
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
                if final || message != nil {
                    let wasRecording = self.isRecording
                    self.stopRecording()
                    if let message, wasRecording { self.onError?(message) }
                }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            stopRecording()
            throw error
        }
    }

    func stopRecording() {
        recordingID = nil
        isStarting = false
        isRecording = false
        engine.stop()
        if hasInputTap { engine.inputNode.removeTap(onBus: 0); hasInputTap = false }
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speak(_ text: String) throws {
        stopRecording()
        synthesizer.stopSpeaking(at: .immediate)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        if !isRecording && !isStarting { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}

extension VoiceService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }
}

enum VoiceError: LocalizedError {
    case speechPermission, microphonePermission, unavailable
    var errorDescription: String? {
        switch self {
        case .speechPermission: return "Speech recognition permission is off. You can enable it for Jarvis-EVO in iOS Settings."
        case .microphonePermission: return "Microphone permission is off. You can enable it for Jarvis-EVO in iOS Settings."
        case .unavailable: return "On-device dictation is unavailable for this device or language. You can still type your message."
        }
    }
}

/// Confines the legacy speech request capture to the realtime tap. No UI or actor
/// state is accessed here. The owning service removes the tap before ending audio.
private final class RecognitionAudioSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
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
