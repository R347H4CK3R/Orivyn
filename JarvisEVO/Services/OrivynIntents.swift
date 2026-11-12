import AppIntents

struct ComposeInOrivynIntent: AppIntent {
    static let title: LocalizedStringResource = "Draft in Orivyn"
    static let description = IntentDescription("Open Orivyn with text waiting for review. This never sends a message or replaces your current draft.")
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Text") var text: String

    init() {}
    init(text: String) { self.text = text }

    @MainActor func perform() async throws -> some IntentResult {
        try IncomingTextInbox.shared.enqueue(text)
        return .result()
    }
}

struct OpenOrivynIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Orivyn"
    static let description = IntentDescription("Open your on-device Orivyn workspace.")
    static let supportedModes: IntentModes = .foreground
    func perform() async throws -> some IntentResult { .result() }
}

struct OrivynShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenOrivynIntent(), phrases: ["Open \(.applicationName)"],
                    shortTitle: "Open Orivyn", systemImageName: "sparkle")
        AppShortcut(intent: ComposeInOrivynIntent(), phrases: ["Draft in \(.applicationName)"],
                    shortTitle: "Draft in Orivyn", systemImageName: "square.and.pencil")
    }
}
