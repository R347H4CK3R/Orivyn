import Foundation

/// This boundary resolves only after cached text-model resources are actually free.
protocol LocalResourceReleasing: Sendable {
    func unload() async
}

enum LocalHeavyWorkKind: Equatable, Sendable { case imageCreation, vision, virtualDesktop, localAgent }

struct LocalHeavyWorkLease: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case preparing, ready, revoked }
    let id: UUID
    let kind: LocalHeavyWorkKind
    var phase: Phase
}

enum LocalHeavyWorkError: Error, LocalizedError, Equatable {
    case busy, background, resourcePressure
    var errorDescription: String? {
        switch self {
        case .busy: "Finish or close the current response, voice, import or image task before starting another memory-intensive feature. Your draft is kept."
        case .background: "Return to Orivyn before starting this feature."
        case .resourcePressure: "Your iPhone needs to cool down or finish releasing memory. Your draft is kept; try again afterward."
        }
    }
}
