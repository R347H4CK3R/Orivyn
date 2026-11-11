import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let isGenerating: Bool
    let isSpeaking: Bool
    let attachmentURL: (ChatAttachment) -> URL?
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
                    Spacer(minLength: 32)
                    VStack(alignment: .leading, spacing: 8) {
                        if !message.content.isEmpty { Text(message.content).textSelection(.enabled) }
                        attachments
                    }
                    .padding(.horizontal, 17).padding(.vertical, 13)
                    .background(Color.evoSurface, in: RoundedRectangle(cornerRadius: 23))
                    .contextMenu { actions }
                }
            } else {
                HStack(spacing: 8) {
                    EvoMark(size: 26)
                    Text("Jarvis-EVO").font(.caption.weight(.semibold))
                    if message.state == .streaming { ProgressView().controlSize(.mini).accessibilityLabel("Generating response") }
                }
                if !message.content.isEmpty {
                    MarkdownContent(text: message.content)
                        .accessibilityIdentifier("assistant.response")
                        .contextMenu { actions }
                } else if message.state == .streaming {
                    Text("Thinking…").font(.subheadline).foregroundStyle(.secondary)
                }
                attachments
                if message.state == .interrupted || message.state == .failed {
                    Label(message.state == .interrupted ? "Response stopped. You can regenerate it." : "Response failed. Choose a model and try again.", systemImage: message.state == .interrupted ? "pause.circle" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if message.state != .streaming {
                    HStack(spacing: 20) {
                        Button(action: onCopy) { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copy response")
                            .disabled(message.content.isEmpty)
                        Button(action: onReadAloud) { Image(systemName: isSpeaking ? "speaker.slash" : "speaker.wave.2") }
                            .accessibilityLabel(isSpeaking ? "Stop reading aloud" : "Read response aloud").disabled(message.content.isEmpty)
                        Button(action: onRegenerate) { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Regenerate in new branch").disabled(isGenerating)
                        Menu { actions } label: { Image(systemName: "ellipsis") }.accessibilityLabel("More message actions")
                    }.font(.system(size: 14)).foregroundStyle(.secondary).buttonStyle(.plain).padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var attachments: some View {
        ForEach(message.attachments) { attachment in
            if let url = attachmentURL(attachment) {
                ShareLink(item: url) {
                    Label(attachment.name, systemImage: "doc.text").font(.caption).lineLimit(2)
                }.accessibilityLabel("Share attachment \(attachment.name)")
            } else {
                Label("\(attachment.name) · text retained", systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
            }
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

private struct MarkdownContent: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if block.isCode {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(block.language.isEmpty ? "Code" : block.language).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            Spacer()
                            Button { UIPasteboard.general.string = block.content } label: { Label("Copy", systemImage: "doc.on.doc").font(.caption) }.buttonStyle(.plain)
                        }.padding(12)
                        Divider()
                        ScrollView(.horizontal) {
                            Text(block.content).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled).padding(14)
                        }
                    }.background(Color.evoSurface, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    Text(markdown(block.content)).font(.body).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func markdown(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
    }

    private var blocks: [(content: String, isCode: Bool, language: String)] {
        var blocks: [(String, Bool, String)] = []
        var current: [String] = []
        var inCode = false
        var language = ""
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if !current.isEmpty { blocks.append((current.joined(separator: "\n"), inCode, language)); current = [] }
                inCode.toggle()
                language = inCode ? String(line.trimmingCharacters(in: .whitespaces).dropFirst(3)) : ""
            } else { current.append(line) }
        }
        if !current.isEmpty { blocks.append((current.joined(separator: "\n"), inCode, language)) }
        return blocks
    }
}

struct EditMessageView: View {
    let message: ChatMessage
    let onSave: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your original conversation stays intact. The edited message starts a new branch.").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $text).padding(8).background(Color.evoSurface, in: RoundedRectangle(cornerRadius: 14)).scrollContentBackground(.hidden)
                    .accessibilityIdentifier("message.edit.input")
            }.padding().navigationTitle("Edit message").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save & send") { onSave(text); dismiss() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { text = message.content }
        }
    }
}
