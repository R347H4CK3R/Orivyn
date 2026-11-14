import SwiftUI
import UniformTypeIdentifiers

struct TextExportView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Set<UUID> = []
    @State private var snapshot: ReviewedTextSnapshot?
    @State private var preparation: Task<Void, Never>?
    @State private var request: UUID?
    @State private var error: String?
    @State private var exporting = false
    @State private var exported = false
    @State private var document = HistoryDocument(data: Data())

    var body: some View {
        List {
            if let snapshot {
                Section("Review selected text") {
                    Text("\(snapshot.conversations.count) conversations · \(snapshot.messageCount) messages · \(snapshot.data.count) bytes")
                    Text("This is a fixed snapshot. The text shown here and conversation metadata, including identifiers and dates, will be saved. Memories, attachment text and original files are excluded.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Prepared \(snapshot.exportedAt.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Save reviewed text…", systemImage: "square.and.arrow.up") {
                        document = HistoryDocument(data: snapshot.data)
                        exporting = true
                    }.disabled(exporting)
                    Button("Change selection") { invalidate() }.disabled(exporting)
                }
                ForEach(snapshot.conversations) { conversation in
                    Section(conversation.title) {
                        Text("\(conversation.messages.count) messages\(conversation.isArchived ? " · Archived" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Created \(conversation.createdAt.formatted()) · Updated \(conversation.updatedAt.formatted())")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(conversation.messages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(message.role.rawValue.capitalized) · \(message.createdAt.formatted())")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(message.content).textSelection(.enabled)
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("Choose completed text-only conversations, including archived ones. Review the exact snapshot before saving it to Files. This is manual transfer, not automatic synchronization.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Up to 100 conversations, 1,000 messages and 5 MB. Conversations with attachments or unfinished messages cannot be selected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Conversations") {
                    ForEach(model.conversations) { conversation in
                        let eligible = conversation.messages.allSatisfy { $0.attachments.isEmpty && $0.state == .complete }
                        Toggle(isOn: Binding(get: { selection.contains(conversation.id) }, set: { selected in
                            if selected { selection.insert(conversation.id) } else { selection.remove(conversation.id) }
                        })) {
                            VStack(alignment: .leading) {
                                Text(conversation.title)
                                Text(eligible ? "\(conversation.messages.count) messages\(conversation.isArchived ? " · Archived" : "")" : "Contains attachments or unfinished messages")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(!eligible || request != nil || (!selection.contains(conversation.id) && selection.count >= ReviewedTextSnapshot.maximumConversations))
                    }
                    if model.conversations.isEmpty { Text("No conversations to export.").foregroundStyle(.secondary) }
                }
                Section {
                    Button("Prepare review") { prepare() }
                        .disabled(selection.isEmpty || request != nil || model.isGenerating)
                    if request != nil { ProgressView("Preparing selected text…") }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Export selected text")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Orivyn-Selected-Text") { result in
            document = HistoryDocument(data: Data())
            switch result {
            case .success: exported = true
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .alert("Selected text exported", isPresented: $exported) { Button("OK", role: .cancel) {} } message: {
            Text("The reviewed snapshot was saved to your chosen location. On another device, use Import conversation backup and choose how matching records are handled. Repeated conflicting imports may create copies.")
        }
        .onChange(of: model.conversations) { _, values in
            invalidate()
            selection.formIntersection(Set(values.map(\.id)))
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { invalidate() } }
        .onDisappear { invalidate() }
    }

    private func prepare() {
        guard request == nil else { return }
        error = nil
        let identity = UUID(), ids = selection
        request = identity
        preparation = Task { @MainActor in
            defer { if request == identity { request = nil; preparation = nil } }
            do {
                let value = try await model.prepareTextExport(ids: ids)
                try Task.checkCancellation()
                guard request == identity else { return }
                snapshot = value
            } catch { if !Task.isCancelled && request == identity { self.error = error.localizedDescription } }
        }
    }
    private func invalidate() {
        preparation?.cancel(); preparation = nil; request = nil; snapshot = nil
        // A document already handed to the system exporter retains its exact
        // bytes until completion. Backgrounding cannot retract a completed save.
    }
}
