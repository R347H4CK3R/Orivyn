import SwiftUI

struct HistoryView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Conversation?
    @State private var newTitle = ""
    @State private var deleting: Conversation?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await model.newConversation(); dismiss() }
                    } label: { Label("New conversation", systemImage: "square.and.pencil").fontWeight(.medium) }
                        .accessibilityIdentifier("history.new")
                    Picker("View", selection: $model.showArchived) {
                        Text("Recent").tag(false)
                        Text("Archived").tag(true)
                    }.pickerStyle(.segmented).listRowSeparator(.hidden)
                }
                Section(model.showArchived ? "Archived conversations" : "Your conversations") {
                    if model.visibleConversations.isEmpty {
                        ContentUnavailableView.search(text: model.searchText)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(model.visibleConversations) { conversation in
                        Button {
                            model.selectConversation(conversation.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bubble.left").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(conversation.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                    Text(conversation.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if conversation.id == model.selectedConversationID { Image(systemName: "checkmark").foregroundStyle(Color.evoAccent).font(.caption.weight(.bold)) }
                            }.padding(.vertical, 5)
                        }
                        .accessibilityIdentifier("history.conversation")
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { newTitle = conversation.title; renaming = conversation }
                            Button(conversation.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                                Task { await model.archive(conversation.id, archived: !conversation.isArchived) }
                            }
                            ShareLink(item: markdown(conversation)) { Label("Share conversation", systemImage: "square.and.arrow.up") }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = conversation }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = conversation }
                            Button(conversation.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                                Task { await model.archive(conversation.id, archived: !conversation.isArchived) }
                            }.tint(.evoAccent)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Rename", systemImage: "pencil") { newTitle = conversation.title; renaming = conversation }.tint(.indigo)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $model.searchText, prompt: "Search conversations")
            .navigationTitle("Conversations")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Rename conversation", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Title", text: $newTitle)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    if let conversation = renaming { Task { await model.rename(conversation.id, to: newTitle) } }
                    renaming = nil
                }
            }
            .confirmationDialog("Delete conversation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete conversation", role: .destructive) {
                    if let conversation = deleting { Task { await model.delete(conversation.id) } }
                    deleting = nil
                }
            } message: { Text("This removes this conversation from this iPhone. Export a backup first if you want to keep it.") }
        }
    }

    private func markdown(_ conversation: Conversation) -> String {
        "# \(conversation.title)\n\n" + conversation.messages.map { message in
            "## \(message.role == .user ? "You" : "Jarvis-EVO")\n\n\(message.content)"
        }.joined(separator: "\n\n")
    }
}
