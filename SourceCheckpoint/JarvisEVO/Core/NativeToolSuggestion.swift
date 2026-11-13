import Foundation

/// A navigation suggestion, never a permission or execution instruction. Only
/// directly typed user text belongs here, not attachments, model or server output.
enum NativeToolSuggestion: String, Identifiable, Sendable {
    case email, calendar, browser, location, reminder

    var id: String { rawValue }
    var title: String {
        switch self {
        case .email: "Email"
        case .calendar: "Calendar"
        case .browser: "Browser"
        case .location: "Location"
        case .reminder: "Reminder"
        }
    }

    static func forText(_ input: String) -> Self? {
        guard input.utf8.count <= 32_768, !input.contains("\0") else { return nil }
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("please ") { text = String(text.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines) }
        // Every expression is anchored. Quotes, code blocks, negations, how-to
        // questions and requests embedded in prose therefore remain ordinary chat.
        let patterns: [(Self, String)] = [
            (.email, #"^(?:draft|write|send|compose)\s+(?:an?\s+)?(?:email|e-mail)\b"#),
            (.calendar, #"^(?:add|create|schedule)\s+(?:an?\s+)?(?:calendar\s+event|event|meeting)\b"#),
            (.browser, #"^(?:open\s+(?:(?:the|a)\s+)?(?:browser|website|web\s+page)\b|(?:open|visit)\s+https://)"#),
            (.location, #"^(?:where\s+am\s+i\b|(?:show|find|get)\s+(?:me\s+)?my\s+(?:current\s+)?location\b)"#),
            (.reminder, #"^(?:remind\s+me\s+(?:to|about|at|in)\b|(?:set|create|schedule|add)\s+(?:a\s+)?reminder\b)"#)
        ]
        return patterns.first { text.range(of: $0.1, options: .regularExpression) != nil }?.0
    }
}
