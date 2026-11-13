import Foundation

enum VoiceError: LocalizedError {
    case speechPermission, microphonePermission, unavailable, noSpeech, finalizationTimeout, emptyPlayback
    var errorDescription: String? {
        switch self {
        case .speechPermission: return "Speech recognition permission is off. You can enable it for Orivyn in iOS Settings."
        case .microphonePermission: return "Microphone permission is off. You can enable it for Orivyn in iOS Settings."
        case .unavailable: return "On-device dictation is unavailable for this device or language. You can still type your message."
        case .noSpeech: return "No speech was detected. Tap the microphone to try again, or type your message."
        case .finalizationTimeout: return "Dictation could not finish. Your partial transcript is kept so you can review and send it yourself."
        case .emptyPlayback: return "There is no text to read aloud."
        }
    }
}
