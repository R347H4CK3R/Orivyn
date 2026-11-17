import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @State private var showModels = false
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
                            Text("Orivyn").font(.headline)
                            Text("Your space. Your models.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Section {
                    NavigationLink { CustomizeWorkspaceView(model: model, openModels: { showModels = true }) } label: {
                        Label("Customize Orivyn", systemImage: "slider.horizontal.3")
                    }
                    Text("Free to use. No paid tiers or in-app unlocks.").font(.footnote).foregroundStyle(.secondary)
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
                    NavigationLink { TextExportView(model: model) } label: {
                        Label("Export selected text…", systemImage: "checklist")
                    }.accessibilityIdentifier("settings.export-text")
                    NavigationLink {
                        ArchiveRestoreView(prepare: { url, progress in try await model.prepareArchiveRestore(url, progress: progress) },
                            commit: { review, progress in try await model.commitArchiveRestore(review, progress: progress) },
                            reloadReviews: { progress in try await model.retainedArchiveReviews(progress: progress) },
                            loadInventory: { review, offset in try await model.retainedArchiveInventory(review, offset: offset) },
                            reloadInventoryReviews: { try await model.retainedArchiveInventoryReviews() },
                            loadAttachmentFiles: { review, offset in try await model.retainedArchiveAttachmentFiles(review, offset: offset) },
                            loadAttachmentMessages: { review, offset, query in try await model.retainedArchiveAttachmentMessages(review, offset: offset, query: query) },
                            reviewAttachment: { review, file, message in try await model.reviewArchiveAttachment(review, file: file, message: message) },
                            commitAttachment: { review, candidate, message, progress in try await model.commitArchiveAttachment(review, candidate: candidate, expectedMessage: message, progress: progress) })
                    } label: { Label("Import complete ChatGPT ZIP", systemImage: "archivebox") }
                        .disabled(model.isGenerating).accessibilityIdentifier("settings.import-chatgpt-zip")
                    NavigationLink { HistoryImportView(model: model) } label: { Label("Import conversation backup", systemImage: "square.and.arrow.down") }.disabled(model.isGenerating)
                } header: { Text("Your data") } footer: {
                    Text("Backups include conversation text, extracted attachment text, and saved memories. Original files, projects, favorites, response preferences and API keys are not included. Keep backups private. Add missing only preserves matching local records. Replacement import overwrites matching conversations and memories, even when the backup is older. Export current data before replacing.")
                }
                Section {
                    Button("Delete all conversations & memories", role: .destructive) { deletingAll = true }
                } footer: { Text("Also removes imported attachment files. Downloaded models and endpoint settings are kept.") }
                Section("Privacy & capabilities") {
                    NavigationLink { RuntimeDiagnosticsView(model: model) } label: { Label("Live diagnostics", systemImage: "waveform.path.ecg") }
                    Label("Conversations are stored on this iPhone.", systemImage: "internaldrive").font(.subheadline)
                    Label("Downloaded models work without a network connection.", systemImage: "wifi.slash").font(.subheadline)
                    Label("Dictation requires on-device speech support and your permission.", systemImage: "mic").font(.subheadline)
                    Text("Local text chat, text/PDF and OCR image attachments, voice controls, projects, favorites, memory and local reminders run on this iPhone. Mail, Calendar, Safari and one-shot location use real system controls and your explicit choices.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Image Playground requires supported iOS 26 settings. Plugin endpoints are optional and require explicit connection and per-call review; they are not on-device services. General visual understanding, autonomous web control, cloud sync and an actual virtual desktop remain unfinished. No external computer is required for local features.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Orivyn is an independent app. It is not affiliated with OpenAI. AI responses can be inaccurate; verify important information.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Help improve Orivyn") {
                    NavigationLink { RepositoryInspectionView() } label: { Label("Inspect private source", systemImage: "doc.text.magnifyingglass") }
                    NavigationLink { SuggestionView() } label: { Label("Send a suggestion", systemImage: "lightbulb") }
                }
                Section("Installed release") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
                    Text(Bundle.main.object(forInfoDictionaryKey: "OrivynReleaseNotes") as? String ?? "Release notes unavailable for this build.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settings.done") } }
            .sheet(isPresented: $showModels) { ModelManagerView(model: model) }
            .fileExporter(isPresented: $exportingHistory, document: document, contentType: .json, defaultFilename: "Orivyn-Backup") { result in
                if case .failure(let error) = result { model.report(error) }
                if case .success = result { exported = true }
            }
            .confirmationDialog("Delete all conversations and memories?", isPresented: $deletingAll, titleVisibility: .visible) {
                Button("Delete all content", role: .destructive) { Task { await model.deleteAllContent() } }
            } message: { Text("This cannot be undone. Export a backup first if you want to keep your data.") }
            .alert("Backup exported", isPresented: $exported) { Button("OK", role: .cancel) {} } message: { Text("Your backup was saved to the location you chose.") }
            .alert("Orivyn", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
    }
}


 // Keep policy selection in a stable navigation destination. Starting a system
 // importer from a confirmation-dialog action can overlap its dismissal and
 // leave a blank presentation (native UI run 43673278573, history import).
private struct HistoryImportView: View {
    @Bindable var model: AppModel
    @State private var importPolicy: BackupImportPolicy = .preserveLocal
    @State private var importingHistory = false
    @State private var confirmation = BackupImportConfirmation()
    @State private var replacementAccessURL: URL?

    var body: some View {
        Form {
            Section("How to import") {
                Picker("Matching records", selection: $importPolicy) {
                    Text("Add missing only (keep local)").tag(BackupImportPolicy.preserveLocal)
                    Text("Keep both versions (copy conflicts)").tag(BackupImportPolicy.keepBoth)
                    Text("Replace matching records…").tag(BackupImportPolicy.replaceMatching)
                }
                .pickerStyle(.inline)
                .accessibilityIdentifier("history.import-policy")
                .disabled(importingHistory || confirmation.pending != nil)
            }
            Section {
                Button("Choose backup file…") {
                    guard confirmation.beginSelection(policy: importPolicy) != nil else { return }
                    importingHistory = true
                }
                    .accessibilityIdentifier("history.import-file")
                    .disabled(model.isGenerating || importingHistory || confirmation.pending != nil)
            } footer: {
                Text("Add missing only keeps all matching local records unchanged. Keep both versions skips identical matching records and imports changed matches as separate copies, preserving the local originals. Repeating a conflicting import creates more copies. With replacement import, matching conversation and memory identifiers are replaced, not combined. An older backup can remove newer messages. Export your current backup first. Original attachment files are not transferred. This is manual import, not automatic synchronization.")
            }
            if let pending = confirmation.pending {
                Section("Confirm replacement") {
                    Text(pending.url.lastPathComponent)
                    Text("Matching conversations and memories will be overwritten. An older backup can remove newer messages. Export your current backup first. Cancel leaves your history unchanged.")
                    Button("Replace matching records", role: .destructive) {
                        guard !model.isGenerating, let request = confirmation.confirm() else { return }
                        // Transfer the access lease into the import task. Navigation
                        // cancellation must not revoke access while it is reading.
                        let accessURL = replacementAccessURL
                        replacementAccessURL = nil
                        Task {
                            defer { accessURL?.stopAccessingSecurityScopedResource() }
                            await model.importHistory(from: request.url, policy: request.policy)
                        }
                    }
                    .disabled(model.isGenerating)
                    .accessibilityIdentifier("history.confirm-replacement")
                    Button("Cancel replacement", role: .cancel) { cancelReplacement() }
                        .accessibilityIdentifier("history.cancel-replacement")
                }
                .accessibilityIdentifier("history.replacement-review")
            }
        }
        .navigationTitle("Import backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importingHistory, allowedContentTypes: [.json], allowsMultipleSelection: false) { [selectionID = confirmation.selectionID] result in
            guard let selectionID, let policy = confirmation.finishSelection(selectionID) else { return }
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    guard confirmation.pending == nil else { return }
                    if let request = confirmation.select(url, policy: policy) {
                        Task { await model.importHistory(from: request.url, policy: request.policy) }
                    } else if url.startAccessingSecurityScopedResource() {
                        replacementAccessURL = url
                    }
                }
            case .failure(let error): model.report(error)
            }
        }
        .onAppear { confirmation.activate() }
        .onDisappear {
            confirmation.invalidate()
            importingHistory = false
            cancelReplacement()
        }
    }

    private func cancelReplacement() {
        confirmation.cancel()
        replacementAccessURL?.stopAccessingSecurityScopedResource()
        replacementAccessURL = nil
    }
}

struct HistoryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct RemoteSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var key = ""
    @State private var enabled = false
    @State private var saving = false
    @State private var removeSavedKey = false
    @State private var saveAttempt: UUID?

    var body: some View {
        Form {
            Section {
                Toggle("Enable remote provider", isOn: $enabled)
                TextField("https://example.com/v1", text: Binding(get: { baseURL }, set: { value in
                    if !RemoteCredentialIntent.sameEndpoint(baseURL, value) {
                        key = ""; removeSavedKey = false; saveAttempt = nil
                    }
                    baseURL = value
                })).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Endpoint base URL")
                TextField("Model identifier", text: $modelName).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Replacement API key (optional)", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("remote.key").disabled(removeSavedKey)
                Toggle("Remove saved key for this endpoint", isOn: $removeSavedKey).accessibilityIdentifier("remote.key.remove")
                Text(RemoteCredentialIntent.sameEndpoint(baseURL, model.remoteBaseURL) && !RemoteCredentialIntent.normalizedEndpoint(baseURL).isEmpty
                     ? "Leave the replacement empty to keep the current endpoint’s saved key. Saved keys are not displayed."
                     : "A blank replacement uses no key. If this endpoint already has a saved key, saving will ask you to replace or explicitly remove it.").font(.caption)
            } header: { Text("OpenAI-compatible endpoint") } footer: {
                Text("Use an HTTPS base URL ending in /v1 if your provider requires it. The app appends /chat/completions. Your API key is stored in this device’s Keychain, never in backups.")
            }
            Section {
                Text("When you select this provider and send a message, conversation text, attachment text, saved memories and response preferences are sent to this endpoint. Its privacy policy, account requirements, and usage charges apply. No messages are sent by saving these settings.")
                    .font(.subheadline)
                Button {
                    guard !saving, scenePhase == .active else { return }
                    let capturedURL = baseURL, capturedModel = modelName, capturedEnabled = enabled
                    let intent = RemoteCredentialIntent.draft(endpoint: capturedURL, savedEndpoint: model.remoteBaseURL, typedKey: key, remove: removeSavedKey)
                    let attempt = UUID(); saveAttempt = attempt; saving = true
                    key = ""; removeSavedKey = false
                    Task { @MainActor in
                        guard scenePhase == .active, saveAttempt == attempt else {
                            if saveAttempt == nil || saveAttempt == attempt { saving = false }
                            return
                        }
                        model.errorMessage = nil
                        await model.saveRemote(baseURL: capturedURL, model: capturedModel, credentialIntent: intent, enabled: capturedEnabled)
                        if saveAttempt == nil { saving = false; return }
                        guard saveAttempt == attempt else { return }
                        saveAttempt = nil; saving = false
                        if model.errorMessage == nil { dismiss() }
                    }
                } label: { if saving { ProgressView() } else { Text("Save endpoint") } }.disabled(saving || (enabled && (baseURL.isEmpty || modelName.isEmpty)))
            }
        }
        .disabled(saving)
        .navigationTitle("Remote endpoint").navigationBarTitleDisplayMode(.inline)
        .onChange(of: Data(RemoteCredentialIntent.normalizedEndpoint(baseURL).utf8)) { _, _ in
            key = ""; removeSavedKey = false; saveAttempt = nil
        }
        .onChange(of: removeSavedKey) { _, remove in if remove { key = "" } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { key = ""; removeSavedKey = false; saveAttempt = nil }
        }
        .onDisappear { key = ""; removeSavedKey = false; saveAttempt = nil }
        .onAppear {
            baseURL = model.remoteBaseURL
            modelName = model.remoteModelName
            enabled = model.remoteEnabled
            key = ""; removeSavedKey = false
        }
    }
}

struct MemoryView: View {
    @Bindable var model: AppModel
    @State private var editor: MemoryEditorItem?
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration = UUID()
    @State private var page: MemorySearch.Page?
    @State private var offset = 0
    @State private var searchError: String?
    var body: some View {
        List {
            Section {
                Text("A bounded selection of notes you save here is added to future conversations. Literal query-word matching and recency choose excerpts; this is not semantic memory or a guarantee every relevant note is found. All originals stay saved. Selected notes are also sent if you choose a remote provider.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let summary = model.lastMemoryContextSummary { Text(summary).font(.caption).foregroundStyle(.secondary) }
                Button { editor = MemoryEditorItem(id: nil, content: "") } label: { Label("Add a memory", systemImage: "plus") }
                NavigationLink { FolderMemoryImportView(model: model) } label: { Label("Import a folder", systemImage: "folder.badge.plus") }
                    .disabled(model.isGenerating)
            }
            Section("Saved notes") {
                if model.memories.isEmpty { Text("No saved memories yet.").foregroundStyle(.secondary) }
                if searchTask != nil { ProgressView("Searching saved notes…") }
                if let searchError { Text(searchError).foregroundStyle(.secondary) }
                if let page {
                    Text("\(page.totalMatches) matching notes · showing \(page.notes.count), starting at \(page.notes.isEmpty ? 0 : offset + 1)").font(.caption)
                    if page.totalMatches == 0 && !model.memories.isEmpty { Text("No matching memories.").foregroundStyle(.secondary) }
                    HStack {
                        Button("Previous") { offset = max(0, offset - 200); search(reset: false) }.disabled(offset == 0)
                        Spacer()
                        Button("Next") { offset += 200; search(reset: false) }.disabled(offset + page.notes.count >= page.totalMatches)
                    }
                }
                ForEach(page?.notes ?? []) { memory in
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
        .searchable(text: $query, prompt: "Search saved notes")
        .onAppear { search(reset: true) }
        .onChange(of: query) { _, _ in search(reset: true) }
        .onChange(of: model.memories) { _, _ in search(reset: true) }
        .onDisappear { searchGeneration = UUID(); searchTask?.cancel(); searchTask = nil }
        .sheet(item: $editor) { item in
            MemoryEditor(content: item.content) { text in await model.saveMemory(id: item.memoryID, content: text) }
        }
    }
    private func search(reset: Bool) {
        searchTask?.cancel()
        let identity = UUID(); searchGeneration = identity
        if reset { offset = 0 }
        page = nil; searchError = nil
        let snapshot = model.memories, text = query, start = offset
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                let result = try await MemorySearch.pageAsync(snapshot, query: text, offset: start)
                guard identity == searchGeneration, !Task.isCancelled else { return }
                page = result
            } catch is CancellationError { }
            catch { if identity == searchGeneration { searchError = text.utf8.count > 1024 ? "Search is limited to 1,024 bytes." : error.localizedDescription } }
            if identity == searchGeneration { searchTask = nil }
        }
    }
}

private struct MemoryEditorItem: Identifiable {
    let id = UUID()
    let memoryID: UUID?
    let content: String
    init(id: UUID?, content: String) { memoryID = id ?? UUID(); self.content = content }
}

private struct MemoryEditor: View {
    @State var content: String
    let save: (String) async -> Bool
    @State private var saving = false
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TextEditor(text: $content).disabled(saving).padding().navigationTitle("Memory note").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Save") {
                            guard !saving else { return }
                            saving = true; saveError = nil
                            Task { @MainActor in
                                let saved = await save(content)
                                saving = false
                                if saved { dismiss() }
                                else { saveError = "The note could not be saved. Your text is kept here; try again." }
                            }
                        }.disabled(saving || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.count > 4_000 || content.utf8.count > 32_768)
                    }
                }
                .interactiveDismissDisabled(saving)
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        if let saveError { Text(saveError).foregroundStyle(.orange) }
                        Text("\(content.count)/4,000 characters · \(content.utf8.count)/32,768 bytes").foregroundStyle(.secondary)
                    }.font(.caption).padding()
                }
        }
    }
}
