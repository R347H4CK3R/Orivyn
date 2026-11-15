import Foundation

/// Syntax assistance only. Reducer and native dispatcher remain the authority.
enum LocalAgentGrammar {
    static func load(requireTool: Bool, conversationIDs: [String] = [], bundle: Bundle = .main) throws -> String {
        guard let url = bundle.url(forResource: "LocalAgentDecision", withExtension: "gbnf"),
              let data = try? Data(contentsOf: url), data.count <= 8_192,
              let source = String(data: data, encoding: .utf8) else { throw LocalAgentError.unavailable }
        return try constrain(source, requireTool: requireTool, conversationIDs: conversationIDs)
    }

    static func constrain(_ source: String, requireTool: Bool, conversationIDs: [String]) throws -> String {
        let header = "root ::= tool | read-result | answer\n"
        guard source.hasPrefix(header), conversationIDs.count <= 60,
              Set(conversationIDs).count == conversationIDs.count,
              conversationIDs.allSatisfy({ UUID(uuidString: $0)?.uuidString.lowercased() == $0 }) else {
            throw LocalAgentError.invalidState
        }
        var lines = source.components(separatedBy: "\n")
        guard let toolIndex = lines.firstIndex(where: { $0.hasPrefix("tool-body ::= ") }),
              let readIndex = lines.firstIndex(where: { $0.hasPrefix("conversation-read ::= ") }) else { throw LocalAgentError.unavailable }
        let alternatives = lines[toolIndex].dropFirst("tool-body ::= ".count).components(separatedBy: " | ")
        guard alternatives.filter({ $0.contains("read_conversation") }).count == 1,
              lines[readIndex].components(separatedBy: "ws string ws").count == 2 else { throw LocalAgentError.unavailable }
        if conversationIDs.isEmpty {
            lines[toolIndex] = "tool-body ::= " + alternatives.filter { !$0.contains("read_conversation") }.joined(separator: " | ")
        } else {
            lines[readIndex] = lines[readIndex].replacingOccurrences(of: "ws string ws", with: "ws conversation-id ws")
            // UUID validation above excludes grammar metacharacters and JSON escapes.
            lines.append("conversation-id ::= " + conversationIDs.sorted().map { "\"\\\"" + $0 + "\\\"\"" }.joined(separator: " | "))
        }
        if requireTool { lines[0] = "root ::= tool" }
        return lines.joined(separator: "\n")
    }
}

extension LocalAgentGrammar {
    static func reviewed(_ policy: LocalReadWorkflowPolicy, bundle: Bundle = .main) throws -> String {
        let original = try load(requireTool:false,bundle:bundle)
        guard policy.actions.count <= 3, policy.canAnswer == policy.actions.isEmpty else { throw LocalAgentError.invalidState }
        var lines=original.components(separatedBy:"\n")
        var choices:[String]=[]
        for (index, action) in policy.actions.enumerated() {
            guard ["search_conversations","read_conversation"].contains(action.name) else { throw LocalAgentError.invalidState }
            let decision=String(decoding:try action.decision.encoded(maximumBytes:4096),as:UTF8.self)
            let encoder=JSONEncoder(); encoder.outputFormatting = .withoutEscapingSlashes
            let literal=String(decoding:try encoder.encode(decision),as:UTF8.self)
            choices.append("approved-\(index)"); lines.append("approved-\(index) ::= " + literal)
        }
        if policy.canAnswer { choices.append("answer") }
        guard !choices.isEmpty else { throw LocalAgentError.invalidState }
        lines[0]="root ::= " + choices.joined(separator:" | ")
        return lines.joined(separator:"\n")
    }
    static func readPlanProposal(kind: String) throws -> String {
        guard ["conversation_read","conversation_search"].contains(kind) else { throw LocalAgentError.invalidState }
        return proposalSource.replacingOccurrences(of:"(search | read)",with:kind=="conversation_read" ? "(read)" : "(search)")
    }
    private static let proposalSource = #"""
root ::= "{" ws "\"schema\"" ws ":" ws "1" ws "," ws "\"kind\"" ws ":" ws (search | read) ws "}"
search ::= "\"conversation_search\"" ws "," ws "\"query\"" ws ":" ws string
read ::= "\"conversation_read\"" ws "," ws "\"query\"" ws ":" ws string ws "," ws "\"title\"" ws ":" ws string ws "," ws "\"messageNumbers\"" ws ":" ws "[" ws index (ws "," ws index)? (ws "," ws index)? ws "]"
index ::= "10000" | [1-9] [0-9]? [0-9]? [0-9]?
ws ::= [ \t\n\r]*
string ::= "\"" char+ "\""
char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F])
"""#
}
