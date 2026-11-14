import Foundation

enum DeskPanel: String, CaseIterable, Identifiable, Sendable {
    case conversation, projects, models
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum DeskScrollAction: Sendable { case up, down, top, bottom }
struct DeskScrollRequest: Identifiable, Sendable {
    let id = UUID()
    let action: DeskScrollAction
}

/// Actual scene events are separate from the user's permission to reveal content.
struct DeskPresentationState {
    private(set) var scrollRequest: DeskScrollRequest?
    private var sessions: Set<String> = []
    private(set) var selectedPanel: DeskPanel = .conversation
    private(set) var isForeground = true
    private(set) var isSharing = false
    var isConnected: Bool { !sessions.isEmpty }
    var connectedDisplayCount: Int { sessions.count }
    var canStartSharing: Bool { isConnected && isForeground }
    mutating func connect(sessionID: String) {
        if sessions.insert(sessionID).inserted { stopSharing() }
    }
    mutating func disconnect(sessionID: String) {
        if sessions.remove(sessionID) != nil { stopSharing() }
    }
    mutating func startSharing() { if canStartSharing { isSharing = true } }
    mutating func stopSharing() { isSharing = false; scrollRequest = nil }
    mutating func setForeground(_ value: Bool) { isForeground = value; if !value { stopSharing() } }
    mutating func select(_ panel: DeskPanel) { selectedPanel = panel; scrollRequest = nil }
    mutating func requestScroll(_ action: DeskScrollAction) {
        guard isSharing && isForeground else { return }
        scrollRequest = DeskScrollRequest(action: action)
    }
}
