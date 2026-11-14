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
