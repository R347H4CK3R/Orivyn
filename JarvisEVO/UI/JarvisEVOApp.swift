import SwiftUI
import AppIntents

@main
struct JarvisEVOApp: App {
    @State private var model: AppModel?
    @State private var startupError: String?
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let fixture = RootViewRegressionFixtureHost.requestedMode {
                    RootViewRegressionFixtureHost(mode: fixture)
                } else { startupContent }
                #else
                startupContent
                #endif
            }
            .onOpenURL { IncomingTextInbox.shared.receive($0) }
            .tint(.evoAccent)
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    model?.stop()
                    Task { await model?.checkpoint() }
                }
            }
        }
    }

    @ViewBuilder private var startupContent: some View {
        if let model { RootView(model: model) }
        else if let startupError {
            ContentUnavailableView {
                Label("Could not open Orivyn", systemImage: "externaldrive.badge.exclamationmark")
            } description: { Text(startupError) } actions: {
                Button("Try again") { Task { await start() } }
            }
        } else { ProgressView("Opening Orivyn…").task { await start() } }
    }

    @MainActor private func start() async {
        do {
            let fileManager = FileManager.default
            var root = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
            root.appendPathComponent(testing ? "JarvisEVOUITests" : "JarvisEVO", isDirectory: true)
            if testing && ProcessInfo.processInfo.arguments.contains("--reset-test-storage"), fileManager.fileExists(atPath: root.path) {
                try fileManager.removeItem(at: root)
            }
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var modelDirectory = root.appendingPathComponent("Models", isDirectory: true)
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            try modelDirectory.setResourceValues(resourceValues)
            let store = try SQLiteConversationStore(url: root.appendingPathComponent("conversations.sqlite"))
            let attachments = try AttachmentService(directory: root.appendingPathComponent("Attachments", isDirectory: true))
            let modelStore = try LocalModelStore(root: modelDirectory)
            let defaults = testing ? UserDefaults(suiteName: "JarvisEVOUITests")! : .standard
            if testing && ProcessInfo.processInfo.arguments.contains("--reset-test-storage") {
                defaults.removePersistentDomain(forName: "JarvisEVOUITests")
            }
            let model = AppModel(store: store, attachmentService: attachments, modelStore: modelStore, defaults: defaults)
            await model.bootstrap()
            ExternalWorkspaceController.shared.configure(model: model)
            self.model = model
            OrivynShortcuts.updateAppShortcutParameters()
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
}

extension Color {
    static let evoAccent = Color.primary
    static let evoSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.96, alpha: 1)
    })
    static let evoSidebar = Color(uiColor: .systemBackground)
    static let evoUserBubble = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.10, green: 0.19, blue: 0.29, alpha: 1) : UIColor(red: 0.91, green: 0.95, blue: 0.99, alpha: 1)
    })
    static let evoUserText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.75, green: 0.86, blue: 1, alpha: 1) : UIColor(red: 0.16, green: 0.35, blue: 0.57, alpha: 1)
    })
}

struct EvoMark: View {
    var size: CGFloat = 38
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30).fill(Color.evoAccent.opacity(0.12))
            Image(systemName: "sparkle").font(.system(size: size * 0.53, weight: .medium)).foregroundStyle(Color.evoAccent)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
