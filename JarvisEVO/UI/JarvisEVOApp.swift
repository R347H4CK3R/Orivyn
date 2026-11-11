import SwiftUI

@main
struct JarvisEVOApp: App {
    @State private var model: AppModel?
    @State private var startupError: String?
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let model { RootView(model: model) }
                else if let startupError {
                    ContentUnavailableView {
                        Label("Could not open Jarvis-EVO", systemImage: "externaldrive.badge.exclamationmark")
                    } description: { Text(startupError) } actions: {
                        Button("Try again") { Task { await start() } }
                    }
                } else { ProgressView("Opening Jarvis-EVO…").task { await start() } }
            }
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
            self.model = model
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
}

extension Color {
    static let evoAccent = Color(red: 0.12, green: 0.46, blue: 0.39)
    static let evoSurface = Color(uiColor: .secondarySystemBackground)
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
