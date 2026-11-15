import Foundation

/// Explicit approved scope only. Neither goals nor result text infer permissions.
struct LocalCompletionContract: Codable, Equatable, Sendable {
    struct Action: Codable, Equatable, Sendable {
        let name: String
        let arguments: MCPJSONValue
        var decision: MCPJSONValue { .object(["type": .string("tool"), "name": .string(name), "arguments": arguments]) }
        init(from decoder: Decoder) throws { try self.init(value: MCPJSONValue(from: decoder)) }
        init(value: MCPJSONValue) throws {
            let object = try LocalCompletionContract.object(value, keys: ["name", "arguments"])
            guard let name = object["name"]?.stringValue,
                  let arguments = object["arguments"], let args = arguments.objectValue else { throw LocalAgentError.invalidState }
            switch name {
            case "get_app_info", "list_models":
                guard args.isEmpty else { throw LocalAgentError.invalidState }
            case "search_memory":
                guard Set(args.keys) == Set(["query", "limit"]), let query = args["query"]?.stringValue,
                      LocalCompletionContract.validText(query, maximum: 256, empty: false),
                      let limit = args["limit"]?.integerValue, (1...10).contains(limit) else { throw LocalAgentError.invalidState }
            default: throw LocalAgentError.invalidState
            }
            self.name = name; self.arguments = arguments
        }
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.matches(name: rhs.name, arguments: rhs.arguments)
        }
        func matches(name: String, arguments: MCPJSONValue) -> Bool {
            guard self.name == name, let expected = self.arguments.objectValue,
                  let actual = arguments.objectValue, Set(expected.keys) == Set(actual.keys) else { return false }
            if name == "search_memory" {
                guard let expectedQuery = expected["query"]?.stringValue,
                      let actualQuery = actual["query"]?.stringValue else { return false }
                return expectedQuery.utf8.elementsEqual(actualQuery.utf8) &&
                    expected["limit"]?.integerValue == actual["limit"]?.integerValue
            }
            return expected.isEmpty && actual.isEmpty
        }
    }
    let schema: Int
    let steps: [Action]
    static func parse(_ text: String) throws -> Self {
        try Self(value: MCPJSONValue.parse(Data(text.utf8), maximumBytes: 4096))
    }
    init(from decoder: Decoder) throws { try self.init(value: MCPJSONValue(from: decoder)) }
    init(value: MCPJSONValue) throws {
        let object = try Self.object(value, keys: ["schema", "steps"])
        guard object["schema"]?.integerValue == 1, let values = object["steps"]?.arrayValue,
              (1...3).contains(values.count) else { throw LocalAgentError.invalidState }
        let actions = try values.map { try Action(value: $0) }
        guard Set(actions.map(\.name)).count == actions.count else { throw LocalAgentError.invalidState }
        schema = 1; steps = actions
    }
    func encoded() throws -> String {
        let value: MCPJSONValue = .object(["schema": .integer(1), "steps": .array(steps.map {
            .object(["name": .string($0.name), "arguments": $0.arguments])
        })])
        return String(decoding: try value.encoded(maximumBytes: 4096), as: UTF8.self)
    }
    /// Structural recovery guard, not proof of on-disk history authenticity.
    /// Failed/malformed result evidence remains retainable for diagnosis.
    func validateRecordedShape(history: [LocalAgentSnapshot.Event], pending: LocalAgentSnapshot.Intent?, approvalRevision: Int?) throws {
        guard approvalRevision == 0, history.count <= steps.count else { throw LocalAgentError.invalidState }
        for (index, event) in history.enumerated() {
            guard steps[index].matches(name: event.name, arguments: event.arguments),
                  ["succeeded", "failed", "interrupted", "cancelled"].contains(event.outcome),
                  event.outcome == "succeeded" || index == history.count - 1,
                  event.outcome == "succeeded" ? event.result != nil : event.result == nil else { throw LocalAgentError.invalidState }
        }
        if let pending {
            guard history.allSatisfy({ $0.outcome == "succeeded" }), history.count < steps.count,
                  steps[history.count].matches(name: pending.name, arguments: pending.arguments) else { throw LocalAgentError.invalidState }
        }
    }
    fileprivate static func object(_ value: MCPJSONValue, keys: [String]) throws -> [String: MCPJSONValue] {
        guard let object = value.objectValue, Set(object.keys) == Set(keys) else { throw LocalAgentError.invalidState }
        return object
    }
    // Match ECMAScript String.trim used by the independent reducer. Foundation's
    // whitespace set differs for U+FEFF and U+0085; never normalize query bytes.
    private static func isReducerWhitespace(_ value: UInt32) -> Bool {
        (0x09...0x0D).contains(value) || (0x2000...0x200A).contains(value) ||
        [0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF].contains(value)
    }
    fileprivate static func validText(_ value: String, maximum: Int, empty: Bool = true) -> Bool {
        value.utf8.count <= maximum && (empty || value.unicodeScalars.contains { !isReducerWhitespace($0.value) }) &&
        !value.unicodeScalars.contains { $0.value < 32 && ![9,10,13].contains($0.value) }
    }
}

/// Independently checks exact approved calls and point-in-time result shapes.
/// A completed checklist does not verify model prose or exhaustiveness.
struct LocalCompletionPolicy: Equatable, Sendable {
    let actions: [LocalCompletionContract.Action]
    let canAnswer: Bool
    static func derive(contract: LocalCompletionContract, history: [LocalAgentSnapshot.Event]) throws -> Self {
        try contract.validateRecordedShape(history: history, pending: nil, approvalRevision: 0)
        for (index, event) in history.enumerated() {
            guard event.outcome == "succeeded", let result = event.result else { throw LocalAgentError.invalidState }
            try validateResult(result, action: contract.steps[index])
        }
        let done = history.count == contract.steps.count
        return Self(actions: done ? [] : [contract.steps[history.count]], canAnswer: done)
    }
    func validate(_ intent: LocalAgentSnapshot.Intent) throws {
        guard actions.contains(where: { $0.matches(name: intent.name, arguments: intent.arguments) }) else { throw LocalAgentError.invalidState }
    }
    private static func validateResult(_ raw: String, action: LocalCompletionContract.Action) throws {
        let value = try MCPJSONValue.parse(Data(raw.utf8), maximumBytes: 4096)
        guard let object = value.objectValue else { throw LocalAgentError.invalidState }
        let hasOmissions = object["resultTruncated"] != nil || object["omittedItems"] != nil
        let omissions: Int64
        if hasOmissions {
            guard object["resultTruncated"]?.boolValue == true,
                  let count = object["omittedItems"]?.integerValue, count > 0, count <= MCPJSONValue.maximumSafeInteger else { throw LocalAgentError.invalidState }
            omissions = count
        } else { omissions = 0 }
        let extras = hasOmissions ? ["resultTruncated", "omittedItems"] : []
        func string(_ value: MCPJSONValue?, maximum: Int) throws {
            guard let text = value?.stringValue, LocalCompletionContract.validText(text, maximum: maximum) else { throw LocalAgentError.invalidState }
        }
        func count(_ key: String, maximum: Int64 = MCPJSONValue.maximumSafeInteger) throws -> Int64 {
            guard let count = object[key]?.integerValue, count >= 0, count <= maximum else { throw LocalAgentError.invalidState }
            return count
        }
        switch action.name {
        case "get_app_info":
            _ = try LocalCompletionContract.object(value, keys: ["app", "assistant", "repository", "repositoryAccess", "capabilities"] + extras)
            for key in ["app", "assistant", "repository", "repositoryAccess"] { try string(object[key], maximum: 1024) }
            guard let capabilities = object["capabilities"]?.arrayValue, omissions <= 24,
                  capabilities.count <= 24 - Int(omissions) else { throw LocalAgentError.invalidState }
            for capability in capabilities {
                let fields = try LocalCompletionContract.object(capability, keys: ["id", "status"])
                try string(fields["id"], maximum: 256)
                guard let status = fields["status"]?.stringValue, ["available", "conditional", "notAvailable"].contains(status) else { throw LocalAgentError.invalidState }
            }
        case "list_models":
            _ = try LocalCompletionContract.object(value, keys: ["models", "totalInstalled", "truncated"] + extras)
            let total = try count("totalInstalled")
            guard let models = object["models"]?.arrayValue, omissions <= 10,
                  Int64(models.count) + omissions == min(total, 10),
                  object["truncated"]?.boolValue == (total > 10) else { throw LocalAgentError.invalidState }
            for model in models {
                let fields = try LocalCompletionContract.object(model, keys: ["id", "name"])
                try string(fields["id"], maximum: 4096); try string(fields["name"], maximum: 4096)
            }
        case "search_memory":
            _ = try LocalCompletionContract.object(value, keys: ["memories", "totalMatchesInWindow", "resultsLimited", "searchedMemories", "searchLimited"] + extras)
            let searched = try count("searchedMemories", maximum: 500)
            let total = try count("totalMatchesInWindow", maximum: searched)
            guard let limit = action.arguments.objectValue?["limit"]?.integerValue,
                  let memories = object["memories"]?.arrayValue, omissions <= limit,
                  Int64(memories.count) + omissions == min(total, limit),
                  object["resultsLimited"]?.boolValue == (total > limit),
                  let searchLimited = object["searchLimited"]?.boolValue,
                  !searchLimited || searched == 500 else { throw LocalAgentError.invalidState }
            var ids = Set<UUID>()
            for memory in memories {
                let fields = try LocalCompletionContract.object(memory, keys: ["id", "excerpt", "excerptMayBeTruncated"])
                guard let rawID = fields["id"]?.stringValue, let id = UUID(uuidString: rawID),
                      rawID.count == 36, ids.insert(id).inserted,
                      fields["excerptMayBeTruncated"]?.boolValue != nil else { throw LocalAgentError.invalidState }
                try string(fields["excerpt"], maximum: 160)
            }
        default: throw LocalAgentError.invalidState
        }
    }
}
