import Foundation

struct LocalReadPlanProposal: Equatable, Sendable {
    let goal: String
    let plan: LocalReadPlan
}

/// A proposal is data, never consent. Only explicit session approval creates a task.
struct LocalReadPlan: Codable, Equatable, Sendable {
    let schema: Int
    let kind: String
    let query: String
    let title: String?
    let messageIndexes: [Int]?

    static func parse(_ text: String) throws -> Self {
        try Self(value: MCPJSONValue.parse(Data(text.utf8), maximumBytes: 4096))
    }
    init(from decoder: Decoder) throws { try self.init(value: MCPJSONValue(from: decoder)) }
    init(value: MCPJSONValue) throws {
        guard let object = value.objectValue, object["schema"]?.integerValue == 1,
              let kind = object["kind"]?.stringValue, ["conversation_search", "conversation_read"].contains(kind),
              let query = object["query"]?.stringValue, Self.bounded(query) else { throw LocalAgentError.invalidState }
        self.schema = 1; self.kind = kind; self.query = query
        if kind == "conversation_read" {
            guard Set(object.keys) == Set(["schema","kind","query","title","messageIndexes"]),
                  let title = object["title"]?.stringValue, Self.bounded(title),
                  let values = object["messageIndexes"]?.arrayValue, (1...3).contains(values.count) else { throw LocalAgentError.invalidState }
            let indexes = values.compactMap { $0.integerValue }.map(Int.init)
            guard indexes.count == values.count, Set(indexes).count == indexes.count,
                  indexes.allSatisfy({ (0...9999).contains($0) }) else { throw LocalAgentError.invalidState }
            self.title = title; messageIndexes = indexes
        } else {
            guard Set(object.keys) == Set(["schema","kind","query"]) else { throw LocalAgentError.invalidState }
            title = nil; messageIndexes = nil
        }
    }
    static func bounded(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 256 &&
        !text.unicodeScalars.contains { $0.value < 32 && ![9,10,13].contains($0.value) }
    }
    static func canonicalTitle(_ text: String) -> String { text.precomposedStringWithCanonicalMapping.lowercased() }
    func encoded() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
    static func proposalPrompt(goal: String, kind: String) throws -> String {
        guard ["conversation_read","conversation_search"].contains(kind), !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, goal.utf8.count <= 512 else { throw LocalAgentError.invalidState }
        let encodedGoal = String(decoding: try JSONEncoder().encode(goal), as: UTF8.self)
        let scope = kind == "conversation_read" ? "Fields: schema1, kind conversation_read, query, exact target title, messageIndexes (1..3 unique zero-based integers; second message=1)." : "Fields: schema1, kind conversation_search, query. No message reads are approved in this mode."
        return "The user selected " + kind + ". Propose that read-only plan for review; do not execute tools or answer. Return JSON. " + scope + " Use the user's actual search words, title and requested message numbers. Do not invent a target or extra reads. A person must inspect the proposal before approval. USER_GOAL_JSON=" + encodedGoal
    }
}
