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
                    ForEach(model.providers) { option in
                        Button {
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
                        .disabled(!option.isAvailable || model.isGenerating)
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
                                    .disabled(model.downloadingModelID != nil || importingBusy)
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
                    Text("Models and precision variants are all free. Downloads use internet; local inference does not. RAM guidance is an estimate, not a guarantee. iOS memory pressure and thermals vary. One local model is loaded at a time with a 2,048-token context. No automatic downloads.")
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
                                    .buttonStyle(.borderless).accessibilityLabel("Remove \(descriptor.name)").disabled(model.isGenerating || importingBusy)
                            }
                        }
                    }
                }
                Section {
                    Button { importing = true } label: { Label("Import GGUF model", systemImage: "folder") }
                        .disabled(importingBusy || model.downloadingModelID != nil)
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
