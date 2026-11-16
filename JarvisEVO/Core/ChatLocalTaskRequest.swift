import Foundation

/// A navigation payload, not a task, approval, or model instruction.
/// Call only with the user's current composer text, never retrieved content.
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

    /// Deterministic proposal from a directly typed request. Still requires
    /// existing checklist review, approval and Run; never grants permission.
    var proposedChecklist: LocalCompletionContract? {
        let text = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let command = lower.hasPrefix("please ") ? String(lower.dropFirst(7)) : lower
        let original = lower.hasPrefix("please ") ? String(text.dropFirst(7)) : text
        let name: String
        let arguments: MCPJSONValue
        if ["list installed models", "list my installed models"].contains(command) {
            name = "list_models"; arguments = .object([:])
        } else if ["show app information", "show the app information"].contains(command) {
            name = "get_app_info"; arguments = .object([:])
        } else if let prefix = ["search saved memory for ", "search saved memories for ", "search my saved memory for "].first(where: { command.hasPrefix($0) }) {
            let query = String(original.dropFirst(prefix.count))
            guard !query.contains("\n"), !query.contains("\r") else { return nil }
            name = "search_memory"
            arguments = .object(["query": .string(query), "limit": .integer(3)])
        } else { return nil }
        return try? LocalCompletionContract(value: .object([
            "schema": .integer(1), "steps": .array([.object([
                "name": .string(name), "arguments": arguments
            ])])
        ]))
    }

    /// Suggestions only open review. A validated checklist can be prefilled,
    /// but is never approved or executed by this navigation payload.
    var suggestsLocalReview: Bool {
        let text = goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.range(of: #"^(?:please\s+)?(?:search\s+(?:my\s+)?saved\s+(?:memory|memories|conversations)\b|list\s+(?:my\s+)?installed\s+models\s*[.!?]?$|show\s+(?:the\s+)?app\s+information\s*[.!?]?$)"#, options: .regularExpression) != nil
    }
}
