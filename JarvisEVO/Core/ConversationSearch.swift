import Foundation

/// Literal local lookup across titles, message text and already-extracted attachment text.
/// Never opens original files or sends queries/content to a provider.
enum ConversationSearch {
    static func matches(_ conversation: Conversation, query: String) -> Bool {
        guard query.utf8.count <= 1024 else { return false }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        func contains(_ text: String) -> Bool {
            text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) != nil
        }
        if contains(conversation.title) { return true }
        return conversation.messages.contains { message in
            contains(message.content) || message.attachments.contains { attachment in
                contains(attachment.name) || attachment.extractedText.map(contains) == true
            }
        }
    }
}
