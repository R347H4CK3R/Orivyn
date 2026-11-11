import SwiftUI

struct HistoryView: View {
    @Bindable var model: AppModel
    let onClose: () -> Void
    let onSettings: () -> Void
    let onModels: () -> Void
    @State private var renaming: Conversation?
    @State private var newTitle = ""
    @State private var deleting: Conversation?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                EvoMark(size: 28)
                Text("Jarvis-EVO").font(.headline)
                Spacer(minLength: 0)
                Button { searchFocused = false; onClose() } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 20)).frame(width: 40, height: 44)
                }.accessibilityLabel("Close history").accessibilityIdentifier("history.close")
            }
            .padding(.leading, 20).padding(.trailing, 12).padding(.top, 4)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $model.searchText)
                    .focused($searchFocused).accessibilityLabel("Search conversations")
                    .accessibilityIdentifier("history.search")
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(Color.evoSurface, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            HStack(spacing: 12) {
                shortcut("Models", image: "cpu", action: onModels)
                shortcut(model.showArchived ? "Recent" : "Archived", image: model.showArchived ? "bubble.left" : "archivebox") {
                    model.showArchived.toggle()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
            Button {
                Task { await model.newConversation(); onClose() }
            } label: {
                Label("New conversation", systemImage: "square.and.pencil")
                    .font(.body.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 14)
            }
            .accessibilityIdentifier("history.new")
            List {
                Section {
                    if model.visibleConversations.isEmpty {
                        Text(model.searchText.isEmpty ? (model.showArchived ? "No archived conversations" : "Your conversations will appear here") : "No matching conversations")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                            .listRowSeparator(.hidden).listRowBackground(Color.clear)
                    }
                    ForEach(model.visibleConversations) { conversation in
                        Button {
                            model.selectConversation(conversation.id)
                            searchFocused = false
                            onClose()
                        } label: {
                            Text(conversation.title)
                                .font(.body).foregroundStyle(.primary).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 13)
                                .background(conversation.id == model.selectedConversationID ? Color.evoSurface : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .accessibilityIdentifier("history.conversation")
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                        .listRowBackground(Color.clear)
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
                            }.tint(.gray)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Rename", systemImage: "pencil") { newTitle = conversation.title; renaming = conversation }.tint(.gray)
                        }
                    }
                } header: {
                    Text(model.showArchived ? "Archived chats" : "Chats").font(.caption).textCase(nil).foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            Divider().padding(.horizontal, 16)
            Button { searchFocused = false; onSettings() } label: {
                HStack(spacing: 12) {
                    Text("J").font(.subheadline.weight(.semibold)).frame(width: 34, height: 34)
                        .background(Color.evoSurface, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Jarvis-EVO").font(.subheadline.weight(.semibold))
                        Text("Settings").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "ellipsis").font(.body)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings").accessibilityIdentifier("settings.open")
        }
        .buttonStyle(.plain)
        .background(Color.evoSidebar)
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

    private func shortcut(_ title: String, image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: image).font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.evoSurface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func markdown(_ conversation: Conversation) -> String {
        "# \(conversation.title)\n\n" + conversation.messages.map { message in
            "## \(message.role == .user ? "You" : "Jarvis-EVO")\n\n\(message.content)"
        }.joined(separator: "\n\n")
    }
}
