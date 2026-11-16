import Foundation

/// A bounded parser for the user's current composer text, never retrieved content.
/// It is not a model instruction or approval for unrelated operations.
struct ChatLocalTaskRequest: Identifiable, Sendable {
    let id = UUID()
    let goal: String

    init?(draft: String, hasAttachments: Bool) {
        guard !hasAttachments, draft.utf8.count <= 512,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.unicodeScalars.contains(where: {
                  $0.value < 32 && $0.value != 9 && $0.value != 10 && $0.value != 13
              }) else { return nil }
        goal = draft
    }

    /// Deterministic scope from a directly typed request. Ordinary chat may
    /// perform this exact local read; the manual checklist still uses its review.
    /// Never grants permission for a model-selected or unrelated operation.
    var proposedChecklist: LocalCompletionContract? {
        let text = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: { "\n\r\t".contains($0) }),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0) || $0.properties.generalCategory == .format }) else { return nil }
        // Delimiters are deliberately explicit. Plain "and" may be query text.
        let split = text.replacingOccurrences(of: #"(?i) and then | then |; *"#,
                                             with: "\u{1F}", options: .regularExpression)
        let clauses = split.components(separatedBy: "\u{1F}")
        guard (1...3).contains(clauses.count) else { return nil }
        var steps: [MCPJSONValue] = []
        for (index, clause) in clauses.enumerated() {
            guard let action = Self.action(clause),
                  action.name != DirectChatRead.searchMemory.rawValue || index == clauses.count - 1 else { return nil }
            steps.append(.object(["name": .string(action.name), "arguments": action.arguments]))
        }
        return try? LocalCompletionContract(value: .object(["schema": .integer(1), "steps": .array(steps)]))
    }

    private static func action(_ text: String) -> LocalCompletionContract.Action? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        let command = lower.hasPrefix("please ") ? String(lower.dropFirst(7)) : lower
        let original = lower.hasPrefix("please ") ? String(trimmed.dropFirst(7)) : trimmed
        let name: DirectChatRead
        let arguments: MCPJSONValue
        if ["list installed models", "list my installed models", "show installed models", "show my installed models"].contains(command) {
            name = .listModels; arguments = .object([:])
        } else if ["show app information", "show the app information", "tell me about this app"].contains(command) {
            name = .getAppInfo; arguments = .object([:])
        } else if let prefix = ["search saved memory for ", "search saved memories for ", "search my saved memory for "].first(where: { command.hasPrefix($0) }) {
            let query = String(original.dropFirst(prefix.count))
            // Query punctuation and words such as "download" are inert data,
            // not permission to invoke anything beyond this exact search.
            // Reject command-shaped appended clauses and handoff envelopes,
            // rather than blacklisting ordinary search vocabulary.
            guard !query.contains("```"),
                  query.range(of: #"(?i)\s+(?:and|then)\s+(?:please\s+)?(?:delete|send|run|execute|install|upload|download|ignore|override|list|show|search)\b"#,
                              options: .regularExpression) == nil,
                  query.range(of: #"(?i)(?:^|\s)(?:plugin result|system message|assistant message|tool result):"#,
                              options: .regularExpression) == nil else { return nil }
            name = .searchMemory
            arguments = .object(["query": .string(query), "limit": .integer(3)])
        } else { return nil }
        return try? LocalCompletionContract.Action(value: .object(["name": .string(name.rawValue), "arguments": arguments]))
    }

    /// Suggestions only open review. A validated checklist can be prefilled,
    /// but is never approved or executed by this navigation payload.
    var suggestsLocalReview: Bool {
        let text = goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.range(of: #"^(?:please\s+)?(?:search\s+(?:my\s+)?saved\s+(?:memory|memories|conversations)\b|list\s+(?:my\s+)?installed\s+models\s*[.!?]?$|show\s+(?:the\s+)?app\s+information\s*[.!?]?$)"#, options: .regularExpression) != nil
    }
}
