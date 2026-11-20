import SwiftUI

/// Optional Web tool sheet. Safari and the chat composer are not inputs.
struct PassageExplanationView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var passage = ""
    @State private var source = ""
    @State private var answer: String?
    @State private var error: String?
    @State private var operation: UUID?
    @State private var worker: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Text("Paste the passage you want explained. Orivyn does not read Safari, open the source link, or send the passage online. Nothing here is saved to your chats.")
            }
            Section("Passage") {
                TextEditor(text: $passage).frame(minHeight: 130)
                    .accessibilityLabel("Passage to explain")
                    .accessibilityIdentifier("passage.text")
                    .disabled(worker != nil)
                if passage.utf8.count > PassageExplanationInput.maximumInputBytes {
                    Text(PassageExplanationError.invalidPassage.localizedDescription)
                }
                TextField("Optional HTTPS source address", text: $source)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("passage.source")
                    .disabled(worker != nil)
            }
            Section {
                if worker != nil {
                    ProgressView("Explaining on this iPhone…")
                    Button("Cancel") { cancel() }.accessibilityIdentifier("passage.cancel")
                } else {
                    Button("Explain on this iPhone") { begin() }
                        .disabled(scenePhase != .active || passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("passage.explain")
                }
                if let error { Text(error).accessibilityIdentifier("passage.error") }
            }
            if let answer {
                Section("Local explanation") {
                    Text(verbatim: answer).textSelection(.enabled)
                    if let url = try? BrowserDestination.validated(source).url {
                        Text("Source link supplied by you (not opened or verified)")
                        Text(verbatim: url.absoluteString).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Explain a passage")
        .onChange(of: passage) { _, _ in answer = nil; error = nil }
        .onChange(of: source) { _, _ in answer = nil; error = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
        .onDisappear { cancel(); passage = ""; source = ""; answer = nil; error = nil }
    }

    private func begin() {
        guard worker == nil, scenePhase == .active else { return }
        let input: PassageExplanationInput
        do { input = try .init(passage: passage, source: source) }
        catch { self.error = error.localizedDescription; return }
        let id = UUID()
        operation = id
        answer = nil
        error = nil
        worker = Task { @MainActor in
            defer { if operation == id { operation = nil; worker = nil } }
            do {
                let output = try await model.explainPassage(input)
                guard !Task.isCancelled, operation == id, scenePhase == .active else { return }
                answer = output
            } catch is CancellationError {
                // A dismissed or superseded view never publishes stale text.
            } catch {
                guard !Task.isCancelled, operation == id, scenePhase == .active else { return }
                if error is PassageExplanationError || error is LocalHeavyWorkError {
                    self.error = error.localizedDescription
                } else {
                    self.error = "The installed model could not explain this passage. Select a verified on-device model and try again."
                }
            }
        }
    }

    private func cancel() {
        operation = nil
        worker?.cancel()
        worker = nil
    }
}
