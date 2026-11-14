import Foundation

/// Allowlisted operational values only: no prompts, replies, IDs, paths or credentials.
struct RuntimeDiagnosticState: Equatable, Sendable {
    var generating = false
    var generatedCharacters = 0
    var preparingModel = false
    var downloadPercent: Int?
    var importingAttachments = false
    var savingImage = false
    var admissionBlocked = false
    var online: Bool?
    var installedModelCount = 0
    var heavyWork = "None"
    var heavyPhase = "None"
    var hasReportedError = false
}

struct RuntimeDiagnosticLog {
    struct Event: Identifiable {
        let id = UUID()
        let date: Date
        let state: RuntimeDiagnosticState
    }
    private(set) var events: [Event] = []
    private(set) var lastChecked: Date?
    var lastChanged: Date? { events.last?.date }
    mutating func observe(_ state: RuntimeDiagnosticState, at date: Date = Date()) {
        lastChecked = date
        guard events.last?.state != state else { return }
        events.append(Event(date: date, state: state))
        if events.count > 200 { events.removeFirst(events.count - 200) }
    }
}
