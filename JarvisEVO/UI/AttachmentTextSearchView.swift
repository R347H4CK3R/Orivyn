import SwiftUI

/// Searches only the stored extraction, without invoking a model or opening the original file.
struct AttachmentTextSearchView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchedQuery: String?
    @State private var result: AttachmentTextSearch.Result?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Find a word or phrase", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { search() }
                        .accessibilityIdentifier("attachment.search.query")
                    Button("Search extracted text", action: search)
                        .accessibilityIdentifier("attachment.search.run")
                } footer: {
                    Text("Offline literal phrase search, ignoring case and accents. Searches up to 60,000 characters of stored extracted text, not the original file. OCR can be incomplete or wrong. Positions are text character offsets, not PDF page numbers. Nothing is sent to a model or server.")
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                if let result, let searchedQuery {
                    Section("Results for \(searchedQuery)") {
                        if result.matches.isEmpty { Text("No matching phrase in the searched text.") }
                        ForEach(Array(result.matches.enumerated()), id: \.offset) { _, match in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Character \(match.offset + 1)").font(.caption).foregroundStyle(.secondary)
                                Text(match.snippet).textSelection(.enabled)
                            }
                        }
                        if result.moreMatches { Text("Showing the first 50 matches. Use a more specific phrase to narrow the results.").foregroundStyle(.secondary) }
                        if result.wasTextTruncated { Text("Only the first 60,000 characters were searched. Later text may contain additional matches.").foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Extracted text search")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func search() {
        result = nil
        searchedQuery = nil
        errorMessage = nil
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a word or phrase to search."
            return
        }
        do {
            result = try AttachmentTextSearch.search(text: text, query: query)
            searchedQuery = query
        } catch {
            errorMessage = "Keep the search phrase within 256 UTF-8 bytes."
        }
    }
}
