import Foundation

/// Snapshot created only by an explicit, disclosed composer action. It is not
/// an approval to execute a tool, install a connection, or transmit attachments.
struct PluginChatRequest: Identifiable, Sendable {
    let id = UUID()
    let goal: String
    let conversation: UUID
    let provider: UUID
    let connection: UUID
    let catalog: UUID

    init?(goal: String, conversation: UUID, provider: UUID, connection: UUID, catalog: UUID) {
        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              goal.utf8.count <= 4096 else { return nil }
        self.goal = goal; self.conversation = conversation; self.provider = provider
        self.connection = connection; self.catalog = catalog
    }
    func matches(conversation: UUID, provider: UUID, connection: UUID?, catalog: UUID) -> Bool {
        self.conversation == conversation && self.provider == provider && self.connection == connection && self.catalog == catalog
    }
}
