import SwiftUI
import UniformTypeIdentifiers

struct ModelManagerView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showFreeOnline = false
    @State private var importing = false
    @State private var importingBusy = false
    @State private var removing: LocalModelDescriptor?
    @State private var catalogQuery = ""
    @State private var catalogPurpose = "All"
    @State private var smallestFirst = false
    private var catalogEntries: [LocalModelCatalogEntry] {
        LocalModelCatalog.filtered(query: catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "everyday" ? "General chat" : catalogQuery, purpose: catalogPurpose, smallestFirst: smallestFirst)
    }

    private struct CatalogGroup: Identifiable {
        let id: String
        let entries: [LocalModelCatalogEntry]
    }
    private var catalogGroups: [CatalogGroup] {
        var order: [String] = []
        var grouped: [String: [LocalModelCatalogEntry]] = [:]
        for entry in catalogEntries {
            if grouped[entry.baseModel] == nil { order.append(entry.baseModel) }
            grouped[entry.baseModel, default: []].append(entry)
        }
        return order.map { CatalogGroup(id: $0, entries: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Auto · choose on this iPhone", isOn: Binding(
                        get: { model.offlineAutoEnabled || model.automaticModelsEnabled },
                        set: { enabled in
                            model.offlineAutoEnabled = enabled
                            if !enabled { model.automaticModelsEnabled = false }
                        }))
                        .accessibilityIdentifier("model.auto.installed")
                        .disabled(model.isGenerating || model.isPreparingAutomaticModel)
                    Text("Chooses an installed task-matching AI, then Apple or an installed general model. Never downloads or sends your text online by itself. Voice keeps your manual choice.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(model.providers.filter { $0.id != "remote" }) { option in
                        providerRow(option)
                    }
                } header: { Text("Works offline") } footer: {
                    Text("Free to chat on this iPhone. Choose an available AI below, or download one. No Orivyn account needed.")
                }
                Section {
                    Button { showFreeOnline = true } label: {
                        Label("Explore free online AI", systemImage: "network")
                            .font(.headline).frame(minHeight: 48)
                    }.accessibilityIdentifier("freeOnline.open")
                } header: { Text("Free online · optional") } footer: {
                    Text("Needs internet and your own OpenRouter key. Opens a separate message, never your saved chats. No paid fallback.")
                }
                // Keep the existing endpoint reachable without presenting it as a free route.
                if model.providers.contains(where: { $0.id == "remote" }) {
                    Section {
                        ForEach(model.providers.filter { $0.id == "remote" }) { option in
                            providerRow(option)
                        }
                    } header: { Text("Needs internet") } footer: {
                        Text("Your configured connection. Not part of the free catalog; charges may apply. It receives your conversation, attachment text and saved memory.")
                    }
                }
                if let downloadingID = model.downloadingModelID {
                    Section("Active download") {
                        Text(LocalModelCatalog.entries.first { $0.id == downloadingID }?.descriptor.name ?? "Model")
                        ProgressView(value: model.downloadProgress ?? 0)
                        Button("Cancel download") { model.cancelDownload() }
                            .accessibilityIdentifier("model.download.cancel")
                    }
                }
                Section {
                    TextField("Find an AI or a task", text: $catalogQuery)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("model.catalog.search")
                    Picker("Purpose", selection: $catalogPurpose) {
                        ForEach(LocalModelCatalog.purposes, id: \.self) { Text($0 == "General chat" ? "Everyday" : $0).tag($0) }
                    }.accessibilityIdentifier("model.catalog.purpose")
                    Toggle("Smallest downloads first", isOn: $smallestFirst)
                    Text("\(catalogEntries.count) downloads · all free · no account or API key")
                        .font(.caption).foregroundStyle(.secondary)
                    if catalogEntries.isEmpty {
                        Text("No matching models. Try a different search or purpose.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(catalogGroups) { group in
                        if let first = group.entries.first {
                            catalogCard(first)
                            if group.entries.count > 1 {
                                DisclosureGroup("More download options") {
                                    ForEach(Array(group.entries.dropFirst())) { entry in
                                        catalogCard(entry)
                                    }
                                }
                                .accessibilityIdentifier("model.variants.\(first.id)")
                            }
                        }
                    }
                } header: { Text("Download for offline chat") } footer: {
                    Text("Models and precision variants are all free. Downloads use internet; local inference does not. RAM guidance is an estimate, not a guarantee. iOS memory pressure and thermals vary. One local model is loaded at a time with a 2,048-token context. Automatic downloads occur only after you enable Automatic and send a request.")
                }
                Section {
                    Toggle("Allow automatic model downloads", isOn: $model.automaticModelsEnabled)
                        .accessibilityIdentifier("model.automatic")
                    if model.automaticModelsEnabled {
                        Toggle("Allow cellular downloads", isOn: $model.automaticAllowsCellular)
                            .accessibilityIdentifier("model.automatic.cellular")
                        Text("Sending may download a verified general model (491 MB) or coding model (1.12 GB), with a 1.2 GB per-request cap. Automatic coding requires at least 6 GB RAM guidance and about 2.34 GB free installation space. Downloads normally require unmetered Wi-Fi or Ethernet. Cellular can use your data allowance. Network transition checks are best-effort; Low Data Mode is always blocked. Existing models are never automatically deleted.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let decision = model.automaticDecision {
                        Text("\(decision.model.name) · \(decision.reason)").font(.caption)
                    }
                } header: { Text("Model routing") } footer: {
                    Text("Separate opt-in: allows Auto to download the pinned general or coding model when needed. Turning downloads off keeps installed-only Auto available. No remote endpoint is selected automatically. Voice uses the manual model.")
                }
                Section("Qwen 3 response mode") {
                    Toggle("Concise Qwen 3 answers", isOn: $model.conciseQwen3)
                        .accessibilityIdentifier("model.qwen.concise")
                        .disabled(model.isGenerating || model.isPreparingAutomaticModel)
                    Text("Optional non-thinking template mode for local Qwen 3 chat. Off preserves the model's default reasoning. This does not hide generated text, guarantee short answers, or change other model families or remote providers. Device behavior still needs verification.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.installedModels.isEmpty {
                    Section("On this iPhone") {
                        ForEach(model.installedModels) { descriptor in
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(descriptor.name).font(.subheadline)
                                    Text(descriptor.formattedSize).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) { removing = descriptor } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless).accessibilityLabel("Remove \(descriptor.name)").disabled(model.isGenerating || importingBusy || model.isPreparingAutomaticModel)
                            }
                        }
                    }
                }
                Section {
                    Button { importing = true } label: { Label("Import GGUF model", systemImage: "folder") }
                        .disabled(importingBusy || model.downloadingModelID != nil || model.isPreparingAutomaticModel)
                    if importingBusy { ProgressView("Checking and importing model…") }
                } footer: { Text("Choose an instruction-tuned GGUF file up to 2 GB with an embedded chat template. Compatibility and available memory vary. Only import models you trust and have permission to use.") }
            }
            .accessibilityIdentifier("model.list")
            .navigationTitle("Choose an AI").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("model.done") } }
            .sheet(isPresented: $showFreeOnline) { FreeOnlineChatView(state: model.freeOnlineChat) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importingBusy = true
                        Task { await model.importModel(from: url); importingBusy = false }
                    }
                case .failure(let error): model.report(error)
                }
            }
            .confirmationDialog("Remove downloaded model?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove model", role: .destructive) {
                    if let descriptor = removing { Task { await model.removeModel(descriptor) } }
                    removing = nil
                }
            } message: { Text("This frees storage. Your conversations remain saved. You can download or import the model again later.") }
            .alert("Model operation failed", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
        .interactiveDismissDisabled(importingBusy)
    }
    private func providerRow(_ option: ProviderOption) -> some View {
                        Button {
                            model.selectManualProvider(option.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.id == "remote" ? "network" : "iphone").foregroundStyle(Color.evoAccent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(option.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    Text(option.detail).font(.subheadline).foregroundStyle(.secondary)
                                    Text(option.isAvailable ? "Ready" : "Unavailable")
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                }
                                Spacer()
                                if model.selectedProviderID == option.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.evoAccent) }
                            }.padding(.vertical, 8).frame(minHeight: 48)
                        }
                        .accessibilityIdentifier("model.provider.\(option.id)")
                        .accessibilityValue(model.selectedProviderID == option.id ? "Selected" : "")
                        .disabled(!option.isAvailable || model.isGenerating || model.isPreparingAutomaticModel)
    }

    @ViewBuilder private func catalogCard(_ entry: LocalModelCatalogEntry) -> some View {
                        let descriptor = entry.descriptor
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.baseModel).font(.headline)
                                        .accessibilityIdentifier("model.catalog.name.\(descriptor.id)")
                                    Text("\(descriptor.formattedSize) · \(entry.quantization) · Free").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.installedModels.contains(where: { $0.id == descriptor.id }) {
                                    Label("Installed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Color.evoAccent)
                                        .accessibilityIdentifier("model.installed.\(descriptor.id)")
                                }
                            }
                            Text("\(entry.purpose) · \(entry.recommendedRAMGB) GB device RAM recommended")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(entry.purpose == "Coding" ? "Help with code drafts and explanations." : entry.purpose == "Reasoning" ? "Explore harder questions, step by step." : "Everyday questions, writing and ideas.").font(.subheadline).foregroundStyle(.secondary)
                            DisclosureGroup("Details · storage and compatibility") {
                            Text(entry.notes).font(.subheadline).foregroundStyle(.secondary)
                            Text("Allow \(entry.formattedFreeStorage) free storage during installation.")
                                .font(.caption).foregroundStyle(.secondary)
                            if !entry.meetsRAMGuidance(physicalMemory: ProcessInfo.processInfo.physicalMemory) {
                                Label("This iPhone is below the suggested RAM. Prefer a smaller model.", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Text("Physical iPhone performance validation pending.").font(.caption).foregroundStyle(.secondary)
                            }.font(.subheadline)
                            if model.downloadingModelID == descriptor.id {
                                Text("Downloading and verifying…").font(.caption).foregroundStyle(.secondary)
                            } else if !model.installedModels.contains(where: { $0.id == descriptor.id }) {
                                Button { model.downloadModel(descriptor) } label: { Label("Download · \(descriptor.formattedSize)", systemImage: "arrow.down.circle").frame(minHeight: 44) }
                                    .accessibilityIdentifier("model.download.\(descriptor.id)")
                                    .disabled(model.downloadingModelID != nil || importingBusy || model.isPreparingAutomaticModel)
                            }
                            HStack {
                                if let url = descriptor.sourceURL { Link("Publisher details", destination: url).font(.caption) }
                                if let url = entry.licenseURL { Link("License", destination: url).font(.caption) }
                            }
                        }
                        // Each control owns its tap; automatic List row actions can also open the link.
                        .buttonStyle(.borderless)
                        .padding(.vertical, 6)
    }

}
