import Foundation

/// Current composer text only. A deliberately bounded natural-language router,
/// not model inference of permission. No history, imports or tool results enter.
struct NaturalLocalReadIntent: Sendable {
    let contract: LocalCompletionContract

    init?(currentText: String, hasAttachments: Bool) {
        guard let bounded = ChatLocalTaskRequest(draft: currentText, hasAttachments: hasAttachments) else { return nil }
        let text = bounded.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: { "\n\r\t".contains($0) }),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format }) else { return nil }
        // Try the whole clause first: "bread and butter" is query data.
        if let action = Self.clause(text) {
            contract = action
            return
        }
        let split = text.replacingOccurrences(of: #"(?i) and then | then | and |; *"#,
                                             with: "\u{1F}", options: .regularExpression)
        let clauses = split.components(separatedBy: "\u{1F}")
        guard (2...3).contains(clauses.count) else { return nil }
        var steps: [MCPJSONValue] = []
        for (index, clause) in clauses.enumerated() {
            guard let action = Self.clause(clause)?.steps.first,
                  action.name != DirectChatRead.searchMemory.rawValue || index == clauses.count - 1 else { return nil }
            steps.append(.object(["name": .string(action.name), "arguments": action.arguments]))
        }
        guard let result = try? LocalCompletionContract(value: .object(["schema": .integer(1), "steps": .array(steps)])) else { return nil }
        contract = result
    }

    private static func clause(_ raw: String) -> LocalCompletionContract? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        var command = text.lowercased()
        if command.hasSuffix("?") { command.removeLast() }
        let canonical: String
        switch command {
        case "what models do i have", "which models are installed", "what models are installed":
            canonical = "list installed models"
        case "what can this app do", "what can orivyn do", "tell me about orivyn":
            canonical = "show app information"
        default:
            let lower = text.lowercased()
            let findPrefix = "find ", findSuffix = " in my saved memories"
            let rememberPrefix = "what do you remember about "
            if lower.hasPrefix(findPrefix), lower.hasSuffix(findSuffix) {
                // ASCII anchors, exact original query bytes between them.
                canonical = "search saved memory for " + String(text.dropFirst(findPrefix.count).dropLast(findSuffix.count))
            } else if lower.hasPrefix(rememberPrefix) {
                canonical = "search saved memory for " + String(text.dropFirst(rememberPrefix.count))
            } else {
                canonical = text
            }
        }
        guard let result = ChatLocalTaskRequest(draft: canonical, hasAttachments: false)?.proposedChecklist,
              result.steps.count == 1 else { return nil }
        return result
    }
}
