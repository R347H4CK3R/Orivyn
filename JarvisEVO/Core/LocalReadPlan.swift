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
    /// Model-facing message numbers are one-based; durable scope stays zero-based.
    /// This is representation conversion only: no goal inference or scope repair.
    static func parseProposal(_ text: String) throws -> Self {
        let value = try MCPJSONValue.parse(Data(text.utf8), maximumBytes: 4096)
        guard var object = value.objectValue else { throw LocalAgentError.invalidState }
        if object["kind"]?.stringValue == "conversation_read" {
            guard Set(object.keys) == Set(["schema", "kind", "query", "title", "messageNumbers"]),
                  let numbers = object["messageNumbers"]?.arrayValue, (1...3).contains(numbers.count) else { throw LocalAgentError.invalidState }
            let integers = numbers.compactMap { $0.integerValue }
            guard integers.count == numbers.count, Set(integers).count == integers.count,
                  integers.allSatisfy({ (1...10000).contains($0) }) else { throw LocalAgentError.invalidState }
            object.removeValue(forKey: "messageNumbers")
            object["messageIndexes"] = .array(integers.map { .integer($0 - 1) })
        }
        return try Self(value: .object(object))
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
        let scope = kind == "conversation_read" ? "Fields: schema=1, kind=conversation_read, query, title, messageNumbers. Copy the requested conversation name into title. Distinguish the name from the surrounding noun: in 'the saved Cedar notes conversation', the name is 'Cedar notes'. Preserve every word inside an explicitly quoted title: 'Cedar conversation' is the full title when quoted. Never replace a specific name with the generic word conversation. Answer-format instructions do not change the requested title. messageNumbers is an array: copy only the requested one-based message numbers without subtracting one. Each number must be from 1 through 10000. The array may contain at least one and at most three unique numbers. Do not fill unused slots or add neighboring messages." : "Fields: schema=1, kind=conversation_search, query. No message reads are approved in this mode."
        return "The user selected " + kind + ". Propose that read-only plan for review; do not execute tools or answer. Return JSON. " + scope + " For query, copy any explicitly requested search text exactly. Otherwise use the conversation title words as the search query, excluding task instructions and question wording. Do not invent a target or extra reads. A person must inspect the proposal before approval. USER_GOAL_JSON=" + encodedGoal
    }
}
