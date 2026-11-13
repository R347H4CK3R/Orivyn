import Foundation

enum LocalAgentError: Error, LocalizedError, Equatable {
    case unavailable, invalidState, storage, localModelRequired, outputBound, staleOwner
    var errorDescription: String? {
        switch self {
        case .unavailable: "The bundled local agent is unavailable. No task was run."
        case .invalidState: "The task or model decision failed validation. Nothing unvalidated was executed."
        case .storage: "Task state could not be safely saved. Work stopped; existing task files were preserved."
        case .localModelRequired: "Select an installed local model first. Local tasks never switch to an online endpoint."
        case .outputBound: "The model response exceeded this task's limit. No tool was dispatched."
        case .staleOwner: "The task no longer owns its model resources. Resume explicitly when ready."
        }
    }
}

