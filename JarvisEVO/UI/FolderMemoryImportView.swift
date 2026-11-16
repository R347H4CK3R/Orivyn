import SwiftUI
import UniformTypeIdentifiers

struct FolderMemoryImportView: View {
    @Bindable var model: AppModel
    @State private var choosing = false
    @State private var active = true
    @State private var scan: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var review: FolderMemoryImport.Review?
    @State private var progress = "Choose the extracted folder, not its ZIP or the entire Downloads folder."
    @State private var failure: String?
    @State private var saving = false

    var body: some View {
        List {
            Section("On-device import") {
                Text("Import UTF-8 text (.txt/.md) and ChatGPT conversations.json as searchable archive excerpts. Media, arbitrary JSON, hidden files and common credential filenames are skipped. Nothing is uploaded during import. Your existing memories stay unchanged.").font(.footnote)
                Button("Choose extracted folder…") { choosing = true }
                    .disabled(scan != nil || saving || model.isGenerating)
                    .accessibilityIdentifier("memory.choose-folder")
                Text(progress).font(.caption).accessibilityIdentifier("memory.import-progress")
                if scan != nil {
                    ProgressView("Reading actual files…")
                    Button("Cancel scan", role: .cancel) { cancel(); progress = "Scan cancelled. No notes saved." }
                }
                if let failure { Text(failure).foregroundStyle(.orange) }
            }
            if let review {
                Section("Review before saving") {
                    Text("\(review.scanned) entries inspected · \(review.skipped) skipped · \(review.notes.count) excerpt notes prepared")
                    Text("Exact-content duplicates are skipped when saving. Source messages include alternate conversation branches and are not verified facts. Imported text cannot authorize tools.").font(.footnote)
                    Text("Selected excerpts may later be sent to your configured remote model. Full archive recall is not guaranteed.").font(.footnote)
                    Button(saving ? "Saving…" : "Add to saved memory") {
                        guard !saving else { return }
                        saving = true
                        Task {
                            let success = await model.importFolderMemories(review.notes)
                            saving = false
                            if success { self.review = nil; progress = model.statusMessage ?? "Import saved." }
                            else { failure = model.errorMessage ?? "Import could not be saved. Review is kept; retry when ready." }
                        }
                    }.disabled(saving || model.isGenerating || review.notes.isEmpty)
                        .accessibilityIdentifier("memory.confirm-folder-import")
                    Button("Discard preview", role: .cancel) { self.review = nil; progress = "Preview discarded. Saved memory was not changed." }.disabled(saving)
                }
                if !review.issues.isEmpty {
                    Section("Files needing attention (\(review.issueCount))") {
                        ForEach(Array(review.issues.enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption) }
                        if review.issueCount > review.issues.count { Text("Showing first \(review.issues.count) issues.") }
                    }
                }
                Section("Preview (first 20 notes)") {
                    ForEach(review.notes.prefix(20)) { note in Text(note.content).font(.caption).lineLimit(8) }
                }
            }
            Section("Limits") {
                Text("20,000 entries, 16 MB per text file or conversation, 1 GB of streamed conversations.json, 40 MB of extracted notes and 10,000 notes per import. Exceeding a limit stops the preview without saving. Split larger exports into smaller text files/subfolders. No automatic ZIP extraction.").font(.footnote)
            }
        }
        .navigationTitle("Import memory folder")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(saving)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { begin(url) }
            case .failure(let error): failure = error.localizedDescription
            }
        }
        .onAppear { active = true }
        .onDisappear { active = false; choosing = false; cancel() }
    }

    private func begin(_ url: URL) {
        guard active else { return }
        cancel(); review = nil; failure = nil
        let identity = UUID(); generation = identity
        progress = "Opening selected folder…"
        scan = Task {
            do {
                let result = try await FolderMemoryReader.read(url) { line in
                    Task { @MainActor in if generation == identity && scan != nil { progress = line } }
                }
                guard generation == identity, !Task.isCancelled else { return }
                review = result
                progress = "Scan finished. Review the excerpts before adding them."
            } catch is CancellationError { }
            catch { if generation == identity { failure = error.localizedDescription } }
            if generation == identity { scan = nil }
        }
    }
    private func cancel() {
        generation = UUID(); scan?.cancel(); scan = nil
    }
}
