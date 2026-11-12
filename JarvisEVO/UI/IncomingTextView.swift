import SwiftUI

struct IncomingTextView: View {
    let request: IncomingTextRequest
    let canAccept: Bool
    let accept: (String) throws -> Void
    let cancel: () -> Void
    @State private var text: String
    @State private var error: String?

    init(request: IncomingTextRequest, canAccept: Bool, accept: @escaping (String) throws -> Void, cancel: @escaping () -> Void) {
        self.request = request; self.canAccept = canAccept; self.accept = accept; self.cancel = cancel
        _text = State(initialValue: request.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This text came from another app or link. Review it before adding it to your draft. Nothing has been sent to a model.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Incoming text") {
                    TextEditor(text: $text).frame(minHeight: 180)
                        .accessibilityLabel("Incoming text").accessibilityIdentifier("incoming.text")
                    Text("\(text.utf8.count)/\(IncomingTextRequest.textByteLimit) UTF-8 bytes")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("Add to draft keeps your current text and attachments. You still choose when to send. Swiping this review away keeps the original incoming text waiting; Cancel discards it.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !canAccept { Text(IncomingTextError.composerBusy.localizedDescription).font(.footnote) }
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("incoming.error") }
                }
            }
            .navigationTitle("Review shared text").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel).accessibilityIdentifier("incoming.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to draft") {
                        do { try accept(text) } catch { self.error = error.localizedDescription }
                    }
                    .disabled(!canAccept || (try? IncomingTextRequest(text: text)) == nil)
                    .accessibilityIdentifier("incoming.accept")
                }
            }
        }
    }
}

struct ShortcutsHelpView: View {
    var body: some View {
        List {
            Section("Shortcuts and sharing") {
                Label("Review before sending", systemImage: "checkmark.shield").font(.headline)
                Text("Orivyn provides Open Orivyn and Draft in Orivyn actions to Apple's Shortcuts app. Draft in Orivyn brings the app to the foreground and stages text for your review. It never runs a model, selects an endpoint or sends automatically.")
            }
            Section("From another app") {
                Text("In Shortcuts, create a shortcut that accepts Text from the Share Sheet. Add Draft in Orivyn and set its Text to Shortcut Input. Enable Show in Share Sheet in that shortcut's details. You can then share text from an app that supports text sharing.")
                Text("This is a Shortcuts workflow, not a separate share extension. Availability depends on iOS registering this signed installation. If actions are missing after sideloading, open Orivyn and Shortcuts again.")
            }
            Section("Text links") {
                Text("You can also open a percent-encoded text link:")
                Text("orivyn://compose?text=Hello%20Orivyn").font(.footnote.monospaced()).textSelection(.enabled)
                Text("Only the compose route and one text parameter are supported. Do not put passwords, tokens or other secrets in URLs; other apps may retain links. Incoming text is limited to 8,192 UTF-8 bytes, with one pending request at a time.")
            }
            Section("What stays on this iPhone") {
                Text("Staging and review need no account, server or paid service. Staged text is held only in memory and is lost if the app is terminated. It is not copied into history until you choose to send it. An optional remote model receives text only when you explicitly send with that provider selected.")
            }
        }.navigationTitle("Shortcuts & sharing").navigationBarTitleDisplayMode(.inline)
    }
}
