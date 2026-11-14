import SwiftUI
import UniformTypeIdentifiers

struct SourceRepairDraftView: View {
    let file: RepositoryInspectionFile
    @Environment(\.dismiss) private var dismiss
    @State private var replacement: String
    @State private var summary = ""
    @State private var draft: SourceRepairDraftCore.Draft?
    @State private var reviewBinding: SourceRepairReviewBinding?
    @State private var error: String?
    @State private var exportingPatch = false
    @State private var patchDocument: SourceRepairPatchDocument?
    @State private var patchFilename = "Orivyn-change.patch"
    @State private var exportStatus: String?
    init(file: RepositoryInspectionFile) {
        self.file = file
        _replacement = State(initialValue: file.text)
    }
    var body: some View {
        Form {
            Section("Local change preview") {
                Text("Edit a proposed replacement and inspect its diff against the verified source. This does not modify GitHub, run code, build an IPA or repair the installed app. Export a patch to keep the reviewed change; unsaved drafts are discarded when this screen closes.").font(.caption)
                Text(file.path).font(.headline)
                Text("Base commit: " + file.commitSHA).font(.caption.monospaced())
                TextField("Single-line change summary", text: $summary)
                TextEditor(text: $replacement).font(.system(.caption, design: .monospaced)).frame(minHeight: 240)
                Text("\(replacement.utf8.count)/131072 bytes").font(.caption)
                Button("Preview local diff") {
                    do {
                        draft = try SourceRepairDraftCore().create(file: file, replacement: replacement, summary: summary)
                        reviewBinding = SourceRepairReviewBinding(replacement: replacement, summary: summary)
                        error = nil; exportStatus = nil
                    }
                    catch { draft = nil; reviewBinding = nil; self.error = error.localizedDescription }
                }.disabled(replacement == file.text || replacement.utf8.count > 131_072 || summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || summary.utf8.count > 500)
                if let error { Text(error).foregroundStyle(.orange) }
            }
            if let draft {
                Section("Draft only · not applied or tested") {
                    Text("Original bytes matched the recorded Git blob before this preview was generated. The remote branch may have changed; any future apply must recheck its base.").font(.caption)
                    ForEach(draft.checks, id: \.self) { Text($0).font(.caption) }
                    ForEach(draft.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    Button("Export reviewed patch…") {
                        guard reviewBinding?.matches(replacement: replacement, summary: summary) == true else {
                            self.draft = nil; reviewBinding = nil
                            error = "The edit changed. Preview the current diff before exporting."
                            return
                        }
                        patchDocument = SourceRepairPatchDocument(data: Data(draft.patch.utf8))
                        patchFilename = draft.exportFilename
                        exportStatus = nil
                        exportingPatch = true
                    }.disabled(reviewBinding?.matches(replacement: replacement, summary: summary) != true)
                    .accessibilityIdentifier("source.patch.export")
                    Text("The patch contains private source snippets and the base commit/blob identity. Choose a storage location you trust; a cloud Files provider may sync it. Saving does not apply or test the change.").font(.caption)
                    if let exportStatus { Text(exportStatus).font(.caption) }
                    Text(draft.diff).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }.disabled(exportingPatch)
        .navigationTitle("Review proposed change")
        .fileExporter(isPresented: $exportingPatch, document: patchDocument,
                      contentType: .plainText, defaultFilename: patchFilename) { result in
            patchDocument = nil
            switch result {
            case .success: exportStatus = "Patch saved to the location you chose. It has not been applied or tested."
            case .failure: exportStatus = "The patch was not saved. Your reviewed draft is still available."
            }
        }
        .interactiveDismissDisabled(exportingPatch)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(exportingPatch) } }
        .onChange(of: replacement) { _, _ in draft = nil; reviewBinding = nil; exportStatus = nil }
        .onChange(of: summary) { _, _ in draft = nil; reviewBinding = nil; exportStatus = nil }
    }
}

/// Immutable bytes captured from one reviewed draft. Only the system file exporter writes them.
private struct SourceRepairPatchDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 310_000 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard !data.isEmpty, data.count <= 310_000 else { throw CocoaError(.fileWriteUnknown) }
        return FileWrapper(regularFileWithContents: data)
    }
}
