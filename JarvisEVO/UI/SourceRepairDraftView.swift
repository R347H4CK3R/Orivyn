import SwiftUI

struct SourceRepairDraftView: View {
    let file: RepositoryInspectionFile
    @Environment(\.dismiss) private var dismiss
    @State private var replacement: String
    @State private var summary = ""
    @State private var draft: SourceRepairDraftCore.Draft?
    @State private var error: String?
    init(file: RepositoryInspectionFile) {
        self.file = file
        _replacement = State(initialValue: file.text)
    }
    var body: some View {
        Form {
            Section("Local change preview") {
                Text("Edit a proposed replacement and inspect its diff against the verified source. This does not modify GitHub, run code, build an IPA or repair the installed app. Drafts are discarded when this screen closes.").font(.caption)
                Text(file.path).font(.headline)
                Text("Base commit: " + file.commitSHA).font(.caption.monospaced())
                TextField("Single-line change summary", text: $summary)
                TextEditor(text: $replacement).font(.system(.caption, design: .monospaced)).frame(minHeight: 240)
                Text("\(replacement.utf8.count)/131072 bytes").font(.caption)
                Button("Preview local diff") {
                    do { draft = try SourceRepairDraftCore().create(file: file, replacement: replacement, summary: summary); error = nil }
                    catch { draft = nil; self.error = error.localizedDescription }
                }.disabled(replacement == file.text || replacement.utf8.count > 131_072 || summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || summary.utf8.count > 500)
                if let error { Text(error).foregroundStyle(.orange) }
            }
            if let draft {
                Section("Draft only · not applied or tested") {
                    Text("Original bytes matched the recorded Git blob before this preview was generated. The remote branch may have changed; any future apply must recheck its base.").font(.caption)
                    ForEach(draft.checks, id: \.self) { Text($0).font(.caption) }
                    ForEach(draft.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    Text(draft.diff).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }.navigationTitle("Review proposed change")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onChange(of: replacement) { _, _ in draft = nil }
        .onChange(of: summary) { _, _ in draft = nil }
    }
}
