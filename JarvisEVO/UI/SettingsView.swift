import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @State private var showModels = false
    @State private var importingHistory = false
    @State private var exportingHistory = false
    @State private var document = HistoryDocument(data: Data())
    @State private var exported = false
    @State private var deletingAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        EvoMark(size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Jarvis-EVO").font(.headline)
                            Text("Your space. Your models.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.pickerStyle(.segmented).accessibilityIdentifier("settings.appearance")
                }
                Section("Intelligence") {
                    Button { showModels = true } label: { Label("Models & storage", systemImage: "cpu") }
                    NavigationLink { MemoryView(model: model) } label: { Label("Saved memory", systemImage: "brain") }
                    NavigationLink { RemoteSettingsView(model: model) } label: { Label("Your remote endpoint", systemImage: "network") }
                }
                Section {
                    Button {
                        Task {
                            do { document = HistoryDocument(data: try await model.exportData()); exportingHistory = true }
                            catch { model.report(error) }
                        }
                    } label: { Label("Export conversation backup", systemImage: "square.and.arrow.up") }
                    Button { importingHistory = true } label: { Label("Import conversation backup", systemImage: "square.and.arrow.down") }.disabled(model.isGenerating)
                } header: { Text("Your data") } footer: {
                    Text("Backups include conversation text, extracted attachment text, and saved memories. Original files and API keys are not included. Keep backups private. Import merges conversations by identifier.")
                }
                Section {
                    Button("Delete all conversations & memories", role: .destructive) { deletingAll = true }
                } footer: { Text("Also removes imported attachment files. Downloaded models and endpoint settings are kept.") }
                Section("Privacy & capabilities") {
                    Label("Conversations are stored on this iPhone.", systemImage: "internaldrive").font(.subheadline)
                    Label("Downloaded models work without a network connection.", systemImage: "wifi.slash").font(.subheadline)
                    Label("Dictation requires on-device speech support and your permission.", systemImage: "mic").font(.subheadline)
                    Text("This version supports text chat, PDF/text attachments, dictation, and read aloud. Web research, image generation, scheduled actions, external tools, and cloud sync are not available.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Jarvis-EVO is an independent app. It is not affiliated with OpenAI. AI responses can be inaccurate; verify important information.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settings.done") } }
            .sheet(isPresented: $showModels) { ModelManagerView(model: model) }
            .fileImporter(isPresented: $importingHistory, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { Task { await model.importHistory(from: url) } }
                case .failure(let error): model.report(error)
                }
            }
            .fileExporter(isPresented: $exportingHistory, document: document, contentType: .json, defaultFilename: "Jarvis-EVO-Backup") { result in
                if case .failure(let error) = result { model.report(error) }
                if case .success = result { exported = true }
            }
            .confirmationDialog("Delete all conversations and memories?", isPresented: $deletingAll, titleVisibility: .visible) {
                Button("Delete all content", role: .destructive) { Task { await model.deleteAllContent() } }
            } message: { Text("This cannot be undone. Export a backup first if you want to keep your data.") }
            .alert("Backup exported", isPresented: $exported) { Button("OK", role: .cancel) {} } message: { Text("Your backup was saved to the location you chose.") }
            .alert("Jarvis-EVO", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
    }
}

struct HistoryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct RemoteSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var key = ""
    @State private var enabled = false
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable remote provider", isOn: $enabled)
                TextField("https://example.com/v1", text: $baseURL).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Endpoint base URL")
                TextField("Model identifier", text: $modelName).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("API key (optional)", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("OpenAI-compatible endpoint") } footer: {
                Text("Use an HTTPS base URL ending in /v1 if your provider requires it. The app appends /chat/completions. Your API key is stored in this device’s Keychain, never in backups.")
            }
            Section {
                Text("When you select this provider and send a message, conversation text, attachment text, and saved memories are sent to this endpoint. Its privacy policy, account requirements, and usage charges apply. No messages are sent by saving these settings.")
                    .font(.subheadline)
                Button {
                    saving = true
                    Task {
                        model.errorMessage = nil
                        await model.saveRemote(baseURL: baseURL, model: modelName, key: key, enabled: enabled)
                        saving = false
                        if model.errorMessage == nil { dismiss() }
                    }
                } label: { if saving { ProgressView() } else { Text("Save endpoint") } }.disabled(saving || (enabled && (baseURL.isEmpty || modelName.isEmpty)))
            }
        }
        .navigationTitle("Remote endpoint").navigationBarTitleDisplayMode(.inline)
        .onChange(of: baseURL) { old, new in
            if !old.isEmpty && old != new { key = "" }
        }
        .onAppear {
            baseURL = model.remoteBaseURL
            modelName = model.remoteModelName
            enabled = model.remoteEnabled
            do { key = try KeychainService.read(endpoint: model.remoteBaseURL) ?? "" } catch { model.report(error) }
        }
    }
}

private struct MemoryView: View {
    @Bindable var model: AppModel
    @State private var editor: MemoryEditorItem?
    var body: some View {
        List {
            Section {
                Text("Only notes you save here are added to future conversations. You can edit or remove them at any time. These notes are also sent if you choose a remote provider.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { editor = MemoryEditorItem(id: nil, content: "") } label: { Label("Add a memory", systemImage: "plus") }
            }
            Section("Saved notes") {
                if model.memories.isEmpty { Text("No saved memories yet.").foregroundStyle(.secondary) }
                ForEach(model.memories) { memory in
                    Button { editor = MemoryEditorItem(id: memory.id, content: memory.content) } label: {
                        Text(memory.content).foregroundStyle(.primary).lineLimit(4)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await model.deleteMemory(memory.id) } }
                    }
                }
            }
        }
        .navigationTitle("Saved memory")
        .sheet(item: $editor) { item in
            MemoryEditor(content: item.content) { text in Task { await model.saveMemory(id: item.memoryID, content: text) } }
        }
    }
}

private struct MemoryEditorItem: Identifiable {
    let id = UUID()
    let memoryID: UUID?
    let content: String
    init(id: UUID?, content: String) { memoryID = id; self.content = content }
}

private struct MemoryEditor: View {
    @State var content: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TextEditor(text: $content).padding().navigationTitle("Memory note").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save(content); dismiss() }.disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.count > 4_000)
                    }
                }
                .safeAreaInset(edge: .bottom) { Text("\(content.count)/4,000 characters").font(.caption).foregroundStyle(.secondary).padding() }
        }
    }
}
