import SwiftUI
import UniformTypeIdentifiers

struct ModelManagerView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var importingBusy = false
    @State private var removing: LocalModelDescriptor?
    @State private var catalogQuery = ""
    @State private var catalogPurpose = "All"
    @State private var smallestFirst = false
    private var catalogEntries: [LocalModelCatalogEntry] {
        LocalModelCatalog.filtered(query: catalogQuery, purpose: catalogPurpose, smallestFirst: smallestFirst)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Automatic local model", isOn: $model.automaticModelsEnabled)
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
                    Text("Opt in to choose a compatible local model for each typed request. No remote endpoint is selected automatically. Turning this off restores your manual choice. Voice uses the manual model.")
                }
                Section("Qwen 3 response mode") {
                    Toggle("Concise Qwen 3 answers", isOn: $model.conciseQwen3)
                        .accessibilityIdentifier("model.qwen.concise")
                        .disabled(model.isGenerating || model.isPreparingAutomaticModel)
                    Text("Optional non-thinking template mode for local Qwen 3 chat. Off preserves the model's default reasoning. This does not hide generated text, guarantee short answers, or change other model families or remote providers. Device behavior still needs verification.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(model.providers) { option in
                        Button {
                            model.automaticModelsEnabled = false
                            model.selectedProviderID = option.id
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.id == "remote" ? "network" : "iphone").foregroundStyle(Color.evoAccent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(option.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    Text(option.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.selectedProviderID == option.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.evoAccent) }
                            }.padding(.vertical, 5)
                        }
                        .accessibilityIdentifier("model.provider.\(option.id)")
                        .accessibilityValue(model.selectedProviderID == option.id ? "Selected" : "")
                        .disabled(!option.isAvailable || model.isGenerating || model.isPreparingAutomaticModel)
                    }
                } header: { Text("Choose a model") } footer: {
                    Text("Local models run on this iPhone. Remote models send your messages, attachment text, and saved memory to the endpoint you configure.")
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
                    TextField("Search models or purpose", text: $catalogQuery)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("model.catalog.search")
                    Picker("Purpose", selection: $catalogPurpose) {
                        ForEach(LocalModelCatalog.purposes, id: \.self) { Text($0).tag($0) }
                    }.accessibilityIdentifier("model.catalog.purpose")
                    Toggle("Smallest downloads first", isOn: $smallestFirst)
                    Text("\(catalogEntries.count) downloads · all free · no account or API key")
                        .font(.caption).foregroundStyle(.secondary)
                    if catalogEntries.isEmpty {
                        Text("No matching models. Try a different search or purpose.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(catalogEntries) { entry in
                        let descriptor = entry.descriptor
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(descriptor.name).font(.subheadline.weight(.semibold))
                                        .accessibilityIdentifier("model.catalog.name.\(descriptor.id)")
                                    Text("\(descriptor.formattedSize) · \(descriptor.license)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.installedModels.contains(where: { $0.id == descriptor.id }) {
                                    Label("Installed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Color.evoAccent)
                                        .accessibilityIdentifier("model.installed.\(descriptor.id)")
                                }
                            }
                            Text("\(entry.purpose) · \(entry.recommendedRAMGB) GB device RAM recommended")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(entry.notes).font(.caption).foregroundStyle(.secondary)
                            Text("Allow \(entry.formattedFreeStorage) free storage during installation.")
                                .font(.caption).foregroundStyle(.secondary)
                            if !entry.meetsRAMGuidance(physicalMemory: ProcessInfo.processInfo.physicalMemory) {
                                Label("This iPhone is below the suggested RAM. Prefer a smaller model.", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Text("Physical iPhone performance validation pending.").font(.caption).foregroundStyle(.secondary)
                            if model.downloadingModelID == descriptor.id {
                                Text("Downloading and verifying…").font(.caption).foregroundStyle(.secondary)
                            } else if !model.installedModels.contains(where: { $0.id == descriptor.id }) {
                                Button { model.downloadModel(descriptor) } label: { Label("Download model", systemImage: "arrow.down.circle") }
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
                } header: { Text("Free model catalog") } footer: {
                    Text("Models and precision variants are all free. Downloads use internet; local inference does not. RAM guidance is an estimate, not a guarantee. iOS memory pressure and thermals vary. One local model is loaded at a time with a 2,048-token context. Automatic downloads occur only after you enable Automatic and send a request.")
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
            .navigationTitle("Models").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("model.done") } }
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
}
