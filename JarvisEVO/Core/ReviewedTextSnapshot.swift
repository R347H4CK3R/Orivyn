import Foundation

/// One immutable, explicitly selected snapshot. This is a file-export value,
/// not peer authentication, transfer consent, or an automatic sync capability.
struct ReviewedTextSnapshot: Sendable {
    static let maximumConversations = 100
    static let maximumMessages = 1_000
    static let maximumBytes = 5_000_000
    let conversations: [Conversation]
    let data: Data
    let exportedAt: Date
    var messageCount: Int { conversations.reduce(0) { $0 + $1.messages.count } }

    init(conversations: [Conversation], exportedAt: Date = Date()) throws {
        guard (1...Self.maximumConversations).contains(conversations.count),
              Set(conversations.map(\.id)).count == conversations.count else { throw TextSnapshotError.selection }
        guard conversations.reduce(0, { $0 + $1.messages.count }) <= Self.maximumMessages else { throw TextSnapshotError.limit }
        var textBytes = 0
        for conversation in conversations {
            guard conversation.title.utf8.count <= 4_096,
                  Set(conversation.messages.map(\.id)).count == conversation.messages.count else { throw TextSnapshotError.limit }
            textBytes += conversation.title.utf8.count
            for message in conversation.messages {
                guard message.attachments.isEmpty else { throw TextSnapshotError.attachments }
                guard message.state == .complete else { throw TextSnapshotError.unfinished }
                guard message.content.utf8.count <= 1_000_000 else { throw TextSnapshotError.limit }
                textBytes += message.content.utf8.count
                guard textBytes <= Self.maximumBytes else { throw TextSnapshotError.limit }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(ConversationBackup(exportedAt: exportedAt, conversations: conversations, memories: []))
        guard bytes.count <= Self.maximumBytes else { throw TextSnapshotError.limit }
        self.conversations = conversations; self.exportedAt = exportedAt; data = bytes
    }
}

enum TextSnapshotError: LocalizedError {
    case selection, changed, attachments, unfinished, limit, busy
    var errorDescription: String? {
        switch self {
        case .selection: "Choose between 1 and 100 conversations."
        case .changed: "A selected conversation is no longer available. Review your selection again."
        case .attachments: "A selected conversation contains attachments. Use the full backup to include its extracted attachment text."
        case .unfinished: "A selected conversation has unfinished, interrupted or failed messages. Only completed messages can be included in this text export."
        case .limit: "Choose fewer or smaller conversations. Text exports support up to 1,000 messages and 5 MB."
        case .busy: "Wait for the current response or history operation to finish before preparing an export."
        }
    }
}
