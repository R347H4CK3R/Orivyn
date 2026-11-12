import SwiftUI

struct SuggestionView: View {
    @Environment(\.openURL) private var openURL
    @State private var draft = FeedbackDraft()
    @State private var error: String?
    private var repository: String { Bundle.main.object(forInfoDictionaryKey: "OrivynFeedbackRepositoryURL") as? String ?? "" }
    var body: some View {
        Form {
            Section {
                TextField("Suggestion title", text: $draft.title).accessibilityIdentifier("suggestion.title")
                Text("\(draft.title.count)/100").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft.details).frame(minHeight: 160).accessibilityLabel("Suggestion details").accessibilityIdentifier("suggestion.details")
                Text("\(draft.details.count)/4,000").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Improve Orivyn") } footer: {
                Text("Describe the problem, desired behavior and how to verify it. Do not include passwords, API keys, financial details or private conversations.")
            }
            Section {
                Button("Open GitHub draft", systemImage: "arrow.up.forward.square") {
                    do {
                        let url = try draft.githubDraftURL(repository: repository)
                        openURL(url) { accepted in if !accepted { error = FeedbackError.cannotOpen.localizedDescription } }
                    } catch { self.error = error.localizedDescription }
                }.disabled(!draft.isValid).accessibilityIdentifier("suggestion.github")
                ShareLink(item: draft.exportText) { Label("Export suggestion", systemImage: "square.and.arrow.up") }.disabled(!draft.isValid)
                if !repository.isEmpty { Text("Project: \(repository)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            } footer: {
                Text("Opening a draft sends only the title and description you entered to GitHub in your browser. Review and submit there using your own account. Visibility follows the repository's access settings. Nothing is submitted automatically and Orivyn stores no GitHub credential.")
            }
            Section("Review and updates") {
                Text("Suggestions are requests, not instructions for trusted code execution. Feasibility, privacy and security need review. Changes require tests and a signed app update. This build does not promise automated review or delivery.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Send a suggestion").navigationBarTitleDisplayMode(.inline)
            .alert("Could not open suggestion", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
}
