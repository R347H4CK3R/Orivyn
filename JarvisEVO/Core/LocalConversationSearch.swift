import Foundation

/// Literal stored-text retrieval only. Never reads attachment files, interprets
/// pixels, or treats a matching saved message as verified factual content.
enum LocalConversationSearch {
    struct Match: Equatable, Sendable {
        let id: UUID
        let title: String
        let excerpt: String
        let excerptMayBeTruncated: Bool
        let evidenceSource: String
    }
    struct Result: Sendable {
        let matches: [Match]
        let searchedConversations: Int
        let searchLimited: Bool
        let totalMatchesInWindow: Int
        var resultsLimited: Bool { totalMatchesInWindow > matches.count }
    }
    static func search(conversations: [Conversation], query: String, limit: Int) throws -> Result {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              query.utf8.count <= 256, (1...10).contains(limit) else { throw LocalAgentError.invalidState }
        var matches: [Match] = []
        var totalMatchesInWindow = 0
        for conversation in conversations.prefix(500) {
            // Inspect the entire reported window even after the result limit.
            guard let evidence = evidence(in: conversation, query: query) else { continue }
            totalMatchesInWindow += 1
            guard matches.count < limit else { continue }
            matches.append(Match(id: conversation.id, title: prefix(conversation.title, bytes: 96),
                excerpt: LocalSearchExcerpt.excerpt(text: evidence.text, query: query),
                excerptMayBeTruncated: evidence.text.utf8.count > 160, evidenceSource: evidence.source))
        }
        return Result(matches: matches, searchedConversations: min(500, conversations.count), searchLimited: conversations.count > 500, totalMatchesInWindow: totalMatchesInWindow)
    }
    private static func evidence(in conversation: Conversation, query: String) -> (text: String, source: String)? {
        // Preserve previous message-over-title preference and failed-message inclusion.
        if let message = conversation.messages.first(where: { contains($0.content, query: query) }) { return (message.content, "message") }
        if contains(conversation.title, query: query) { return (conversation.title, "title") }
        for message in conversation.messages {
            for attachment in message.attachments {
                if contains(attachment.name, query: query) { return (attachment.name, "attachment_name") }
                if let text = attachment.extractedText, contains(text, query: query) { return (text, "attachment_text") }
            }
        }
        return nil
    }
    private static func contains(_ text: String, query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) != nil
    }
    private static func prefix(_ text: String, bytes: Int) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            let next = String(scalar)
            guard result.utf8.count + next.utf8.count <= bytes else { break }
            result += next
        }
        return result
    }
}
