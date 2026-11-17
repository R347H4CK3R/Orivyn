import Foundation

/// Read-only counts of reference records retained by a prepared plan. This is
/// neither a file mapping nor proof an attachment exists, works, or was activated.
/// Opaque original JSON and arbitrary source labels never enter display models.
enum ArchiveRestoreInventory {
    enum Failure: LocalizedError {
        case invalid, limit, offset
        var errorDescription: String? {
            switch self {
            case .invalid: "This retained inventory has missing or ambiguous message identities and cannot be displayed safely."
            case .limit: "This retained inventory exceeds the safe display limits. The preparation was not changed."
            case .offset: "This inventory page is no longer available. Refresh the retained inventory."
            }
        }
    }
    struct Reference: Sendable { let messageID: UUID; let source: String }
    struct Entry: Identifiable, Sendable {
        let id: UUID
        let conversationID: UUID
        let title: String
        let messageIndex: Int
        let role: MessageRole
        let contentPartCount: Int
        let attachmentMetadataCount: Int
        let otherCount: Int
        var totalRecords: Int { contentPartCount + attachmentMetadataCount + otherCount }
    }
    struct Page: Sendable {
        let entries: [Entry]
        let totalMessages: Int
        let totalRecords: Int
        let offset: Int
        var remaining: Int { max(0, totalMessages - offset - entries.count) }
        var nextOffset: Int? { remaining == 0 ? nil : offset + entries.count }
    }
    static func page(conversations: [Conversation], references: [Reference], offset: Int = 0) throws -> Page {
        guard conversations.count <= 10_000, references.count <= 20_000 else { throw Failure.limit }
        guard offset >= 0 else { throw Failure.offset }
        var counts: [UUID: (parts: Int, attachments: Int, other: Int)] = [:]
        for reference in references {
            try Task.checkCancellation()
            guard reference.source.utf8.count <= 4096 else { throw Failure.limit }
            var item = counts[reference.messageID] ?? (0, 0, 0)
            switch reference.source {
            case "contentPart": item.parts += 1
            case "attachmentMetadata": item.attachments += 1
            default: item.other += 1
            }
            counts[reference.messageID] = item
        }
        var conversationsSeen = Set<UUID>(), messagesSeen = Set<UUID>()
        var entries: [Entry] = []
        for conversation in conversations {
            try Task.checkCancellation()
            guard conversationsSeen.insert(conversation.id).inserted else { throw Failure.invalid }
            guard conversation.messages.count <= 50_000,
                  messagesSeen.count <= 500_000 - conversation.messages.count else { throw Failure.limit }
            // Scalar-first bounding also handles adversarial huge grapheme clusters.
            let title = String(String.UnicodeScalarView(conversation.title.unicodeScalars.lazy
                .filter { !CharacterSet.controlCharacters.contains($0) }.prefix(200)))
            for (index, message) in conversation.messages.enumerated() {
                try Task.checkCancellation()
                guard messagesSeen.insert(message.id).inserted else { throw Failure.invalid }
                if let count = counts.removeValue(forKey: message.id) {
                    entries.append(.init(id: message.id, conversationID: conversation.id, title: title,
                        messageIndex: index + 1, role: message.role, contentPartCount: count.parts,
                        attachmentMetadataCount: count.attachments, otherCount: count.other))
                }
            }
        }
        guard counts.isEmpty else { throw Failure.invalid }
        guard offset <= entries.count else { throw Failure.offset }
        return Page(entries: Array(entries.dropFirst(offset).prefix(50)), totalMessages: entries.count,
                    totalRecords: references.count, offset: offset)
    }
}
