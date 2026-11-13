import Foundation

/// Shared native read-only tool implementation; no network or model interpretation.
@MainActor
enum LocalReadTools {
    static func execute(name: String, arguments: MCPJSONValue, model: AppModel) throws -> String {
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
                  let query = args["query"]?.stringValue, !query.isEmpty, query.utf8.count <= 256,
                  let limit = args["limit"]?.integerValue, (1...10).contains(limit) else { throw LocalAgentError.invalidState }
            let matches = model.conversations.prefix(500).filter {
                $0.title.localizedCaseInsensitiveContains(query) || $0.messages.contains { $0.content.localizedCaseInsensitiveContains(query) }
            }.prefix(Int(limit)).map { conversation -> MCPJSONValue in
                let excerpt = conversation.messages.first { $0.content.localizedCaseInsensitiveContains(query) }?.content ?? ""
                return .object(["id": .string(conversation.id.uuidString), "title": .string(Self.prefix(conversation.title, bytes: 96)), "excerpt": .string(Self.prefix(excerpt, bytes: 160)), "excerptMayBeTruncated": .bool(excerpt.utf8.count > 160)])
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
                    "excerpt": .string(Self.prefix(note.content, bytes: 160)),
                    "excerptMayBeTruncated": .bool(note.content.utf8.count > 160)])
            }
            object = .object(["memories": .array(memories),
                "searchedMemories": .integer(Int64(min(500, model.memories.count))),
                "searchLimited": .bool(model.memories.count > 500)])
        default: throw LocalAgentError.invalidState
        }
        let data = try object.encoded(maximumBytes: name == "search_memory" ? 16_384 : 4096)
        guard let text = String(data: data, encoding: .utf8) else { throw LocalAgentError.invalidState }
        return text
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
