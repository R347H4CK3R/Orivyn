import Foundation

/// Shared native read-only tool implementation; no network or model interpretation.
@MainActor
enum LocalReadTools {
    static func execute(name: String, arguments: MCPJSONValue, model: AppModel, resultByteLimit: Int? = nil, trustedGoal: String? = nil) throws -> String {
        if name == "calculate" {
            guard let trustedGoal else { throw LocalAgentError.invalidState }
            return try LocalCalculatorTool.execute(arguments: arguments, requestedGoal: trustedGoal, maximumBytes: resultByteLimit ?? 4096)
        }
        let object: MCPJSONValue
        switch name {
        case "get_app_info":
            guard arguments.objectValue?.isEmpty == true else { throw LocalAgentError.invalidState }
            let capabilities = AppSelfKnowledge.load()?.capabilities.prefix(24).map { MCPJSONValue.object(["id": .string($0.id), "status": .string($0.status.rawValue)]) } ?? []
            object = .object(["app": .string("Orivyn"), "assistant": .string("Jarvis"),
                "repository": .string("https://github.com/R347H4CK3R/Orivyn"),
                "repositoryAccess": .string("Private. This tool reads bundled metadata, not repository source."),
                "capabilities": .array(capabilities)])
        case "list_models":
            guard arguments.objectValue?.isEmpty == true else { throw LocalAgentError.invalidState }
            let models = model.installedModels.prefix(10).map { MCPJSONValue.object(["id": .string(String($0.id.prefix(96))), "name": .string(String($0.name.prefix(96)))]) }
            object = .object(["models": .array(models), "totalInstalled": .integer(Int64(model.installedModels.count)), "truncated": .bool(model.installedModels.count > 10)])
        case "search_conversations":
            guard let args = arguments.objectValue, Set(args.keys) == Set(["query", "limit"]),
                  let query = args["query"]?.stringValue, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.utf8.count <= 256,
                  let limit = args["limit"]?.integerValue, (1...10).contains(limit) else { throw LocalAgentError.invalidState }
            let matches = model.conversations.prefix(500).filter {
                Self.contains($0.title, query: query) || $0.messages.contains { Self.contains($0.content, query: query) }
            }.prefix(Int(limit)).map { conversation -> MCPJSONValue in
                let excerpt = conversation.messages.first { Self.contains($0.content, query: query) }?.content ?? conversation.title
                return .object(["id": .string(conversation.id.uuidString), "title": .string(Self.prefix(conversation.title, bytes: 96)), "excerpt": .string(LocalSearchExcerpt.excerpt(text: excerpt, query: query)), "excerptMayBeTruncated": .bool(excerpt.utf8.count > 160)])
            }
            object = .object(["matches": .array(matches), "searchedConversations": .integer(Int64(min(500, model.conversations.count))), "searchLimited": .bool(model.conversations.count > 500)])
        case "search_memory":
            guard let args = arguments.objectValue, Set(args.keys) == Set(["query", "limit"]),
                  let query = args["query"]?.stringValue,
                  !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.utf8.count <= 256,
                  let limit = args["limit"]?.integerValue, (1...10).contains(limit) else { throw LocalAgentError.invalidState }
            let memories = model.memories.prefix(500).filter {
                $0.content.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }.prefix(Int(limit)).map { note in
                MCPJSONValue.object(["id": .string(note.id.uuidString),
                    "excerpt": .string(LocalSearchExcerpt.excerpt(text: note.content, query: query)),
                    "excerptMayBeTruncated": .bool(note.content.utf8.count > 160)])
            }
            object = .object(["memories": .array(memories),
                "searchedMemories": .integer(Int64(min(500, model.memories.count))),
                "searchLimited": .bool(model.memories.count > 500)])
        default: throw LocalAgentError.invalidState
        }
        let data: Data
        if let resultByteLimit {
            let collection: String
            switch name {
            case "get_app_info": collection = "capabilities"
            case "list_models": collection = "models"
            case "search_conversations": collection = "matches"
            case "search_memory": collection = "memories"
            default: throw LocalAgentError.invalidState
            }
            data = try LocalToolResultBudget.encode(object, collection: collection, maximumBytes: resultByteLimit)
        } else {
            data = try object.encoded(maximumBytes: name == "search_conversations" ? 20_480 : (name == "search_memory" ? 16_384 : 4096))
        }
        guard let text = String(data: data, encoding: .utf8) else { throw LocalAgentError.invalidState }
        return text
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
