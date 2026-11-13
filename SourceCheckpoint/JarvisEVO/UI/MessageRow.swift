import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let isGenerating: Bool
    let isSpeaking: Bool
    let attachmentURL: (ChatAttachment) -> URL?
    let attachmentPreviewURL: (ChatAttachment) -> URL?
    @State private var previewAttachment: ChatAttachment?
    let onCopy: () -> Void
    let onReadAloud: () -> Void
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onBranch: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 58)
                    VStack(alignment: .leading, spacing: 8) {
                        if !message.content.isEmpty { Text(message.content).textSelection(.enabled) }
                        attachments
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .foregroundStyle(Color.evoUserText)
                    .background(Color.evoUserBubble, in: RoundedRectangle(cornerRadius: 24))
                    .contextMenu { actions }
                    .accessibilityIdentifier("user.message")
                }
            } else {
                if !message.content.isEmpty {
                    RichMessageContent(text: message.content)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("assistant.response")
                        .contextMenu { actions }
                } else if message.state == .streaming {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini)
                        Text("Thinking…").font(.subheadline).foregroundStyle(.secondary)
                    }.accessibilityLabel("Generating response")
                }
                attachments
                if message.state == .interrupted || message.state == .failed {
                    Label(message.state == .interrupted ? "Response stopped. You can regenerate it." : "Response failed. Choose a model and try again.", systemImage: message.state == .interrupted ? "pause.circle" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if message.state != .streaming {
                    HStack(spacing: 18) {
                        Button(action: onCopy) { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copy response")
                            .disabled(message.content.isEmpty)
                        Button(action: onReadAloud) { Image(systemName: isSpeaking ? "speaker.slash" : "speaker.wave.2") }
                            .accessibilityLabel(isSpeaking ? "Stop reading aloud" : "Read response aloud").disabled(message.content.isEmpty)
                        Button(action: onRegenerate) { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Regenerate in new branch").disabled(isGenerating)
                        ShareLink(item: message.content) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share response").disabled(message.content.isEmpty)
                        Menu { actions } label: { Image(systemName: "ellipsis") }.accessibilityLabel("More message actions")
                    }.font(.system(size: 15)).foregroundStyle(.secondary).buttonStyle(.plain).padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $previewAttachment) { attachment in
            AttachmentPreviewView(attachment: attachment, originalURL: attachmentURL(attachment), previewURL: attachmentPreviewURL(attachment))
        }
    }

    @ViewBuilder private var attachments: some View {
        ForEach(message.attachments) { attachment in
            AttachmentTile(attachment: attachment, previewURL: attachmentPreviewURL(attachment), open: { previewAttachment = attachment })
        }
    }

    @ViewBuilder private var actions: some View {
        Button("Copy", systemImage: "doc.on.doc", action: onCopy).disabled(message.content.isEmpty)
        ShareLink(item: message.content) { Label("Share", systemImage: "square.and.arrow.up") }.disabled(message.content.isEmpty)
        Button("Select text", systemImage: "text.cursor", action: onSelect).disabled(message.content.isEmpty)
        if message.role == .user {
            Button("Edit in new branch", systemImage: "pencil", action: onEdit).disabled(isGenerating)
        } else {
            Button(isSpeaking ? "Stop reading aloud" : "Read aloud", systemImage: "speaker.wave.2", action: onReadAloud).disabled(message.content.isEmpty)
            Button("Regenerate in new branch", systemImage: "arrow.clockwise", action: onRegenerate).disabled(isGenerating)
        }
        Button("Branch from here", systemImage: "arrow.triangle.branch", action: onBranch).disabled(isGenerating)
    }
}

struct EditMessageView: View {
    let message: ChatMessage
    let onSave: (String) async -> Bool
    @State private var text = ""
    @State private var saving = false
    @State private var saveError: String?
    @State private var initialized = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your original conversation stays intact. The edited message starts a new branch.").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $text).disabled(saving).padding(8).background(Color.evoSurface, in: RoundedRectangle(cornerRadius: 14)).scrollContentBackground(.hidden)
                    .accessibilityIdentifier("message.edit.input")
                if let saveError { Text(saveError).foregroundStyle(.orange) }
            }.padding().navigationTitle("Edit message").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Save & send") {
                            guard !saving else { return }
                            saving = true; saveError = nil
                            Task { @MainActor in
                                let saved = await onSave(text); saving = false
                                if saved { dismiss() }
                                else { saveError = "The edit was not saved. Your text is kept here; check the model, conversation or storage error and try again." }
                            }
                        }.disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.utf8.count > 1_000_000)
                    }
                }
                .interactiveDismissDisabled(saving)
                .onAppear { if !initialized { text = message.content; initialized = true } }
        }
    }
}
