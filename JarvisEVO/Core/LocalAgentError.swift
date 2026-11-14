import Foundation

enum LocalAgentError: Error, LocalizedError, Equatable {
    case unavailable, invalidState, storage, localModelRequired, outputBound, staleOwner
    case nativeGenerationFailed(status: Int32, elapsedSeconds: Double)
    var errorDescription: String? {
        switch self {
        case .unavailable: "The bundled local agent is unavailable. No task was run."
        case .invalidState: "The task or model decision failed validation. Nothing unvalidated was executed."
        case .storage: "Task state could not be safely saved. Work stopped; existing task files were preserved."
        case .localModelRequired: "Select an installed local model first. Local tasks never switch to an online endpoint."
        case .outputBound: "The model response exceeded this task's limit. No tool was dispatched."
        case .nativeGenerationFailed(let status, let elapsed):
            "Native read generation stopped: \(Self.nativeStatusDescription(status)) (code \(status), \(Int(elapsed)) seconds). No read was executed."
        case .staleOwner: "The task no longer owns its model resources. Resume explicitly when ready."
        }
    }
    private static func nativeStatusDescription(_ status: Int32) -> String {
        switch status {
        case 1: "invalid generation arguments"
        case 2: "cancelled"
        case 3: "the generation deadline expired"
        case 4: "model/context ownership or empty-context check failed"
        case 5: "the prompt exceeded the context limit"
        case 6: "native sampler setup failed"
        case 7: "native decoding failed"
        case 8: "the output exceeded its byte limit"
        case 9: "the token limit was reached before completion"
        case 10: "the completed model response failed read validation"
        case 11: "an internal native error occurred"
        case 12: "the one-shot session was already used"
        default: "an unknown native status was returned"
        }
    }
}
