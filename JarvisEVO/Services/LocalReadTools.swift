import Foundation

/// Shared native read-only tool implementation; no network or model interpretation.
@MainActor
enum LocalReadTools {
    static func execute(name: String, arguments: MCPJSONValue, model: AppModel, resultByteLimit: Int? = nil, trustedGoal: String? = nil, authorizedConversationIDs: Set<UUID> = [], reviewedPlan: LocalReadPlan? = nil) throws -> String {
        if name == "search_conversations", let plan=reviewedPlan {
            guard arguments == .object(["query":.string(plan.query),"limit":.integer(10)]),resultByteLimit==4096 else { throw LocalAgentError.invalidState }
            return String(decoding:try LocalReviewedSearch.result(plan:plan,conversations:model.conversations).encoded(maximumBytes:4096),as:UTF8.self)
        }
        if name == "calculate" {
            guard let trustedGoal else { throw LocalAgentError.invalidState }
            return try LocalCalculatorTool.execute(arguments: arguments, requestedGoal: trustedGoal, maximumBytes: resultByteLimit ?? 4096)
        }
        if name == "read_conversation" {
            let page = try LocalConversationRead.read(conversations: model.conversations, arguments: arguments, authorizedIDs: authorizedConversationIDs)
            let data = try page.encoded(maximumBytes: resultByteLimit ?? 4096)
            guard let text = String(data: data, encoding: .utf8) else { throw LocalAgentError.invalidState }
            return text
        }
        let object: MCPJSONValue
        switch name {
        case "get_app_info":
            guard arguments.objectValue?.isEmpty == true else { throw LocalAgentError.invalidState }
            let capabilities = AppSelfKnowledge.load()?.capabilities.prefix(24).map { MCPJSONValue.object(["id": .string($0.id), "status": .string($0.status.rawValue)]) } ?? []
            object = .object(["app": .string("Orivyn"), "assistant": .string("Jarvis"),
                "repository": .string("https://github.com/R347H4CK3R/Orivyn"),
                "repositoryAccess": .string("This tool reads bundled metadata, not repository source. A repository URL does not grant chat source access."),
                "capabilities": .array(capabilities)])
        case "list_models":
            guard arguments.objectValue?.isEmpty == true else { throw LocalAgentError.invalidState }
            let models = model.installedModels.prefix(10).map { MCPJSONValue.object(["id": .string(String($0.id.prefix(96))), "name": .string(String($0.name.prefix(96)))]) }
            object = .object(["models": .array(models), "totalInstalled": .integer(Int64(model.installedModels.count)), "truncated": .bool(model.installedModels.count > 10)])
        case "search_conversations":
            guard let args = arguments.objectValue, Set(args.keys) == Set(["query", "limit"]),
                  let query = args["query"]?.stringValue, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.utf8.count <= 256,
                  let limit = args["limit"]?.integerValue, (1...10).contains(limit) else { throw LocalAgentError.invalidState }
            let result = try LocalConversationSearch.search(conversations: model.conversations, query: query, limit: Int(limit))
            let matches = result.matches.map { match -> MCPJSONValue in
                .object(["id": .string(match.id.uuidString), "title": .string(match.title),
                    "excerpt": .string(match.excerpt), "excerptMayBeTruncated": .bool(match.excerptMayBeTruncated),
                    "evidenceSource": .string(match.evidenceSource)])
            }
            let fields: [String:MCPJSONValue] = ["matches": .array(matches), "searchedConversations": .integer(Int64(result.searchedConversations)), "searchLimited": .bool(result.searchLimited),
                "totalMatchesInWindow": .integer(Int64(result.totalMatchesInWindow)), "resultsLimited": .bool(result.resultsLimited)]
            object = .object(fields)
        case "search_memory":
            guard let args = arguments.objectValue, Set(args.keys) == Set(["query", "limit"]),
                  let query = args["query"]?.stringValue,
                  !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.utf8.count <= 256,
                  let limit = args["limit"]?.integerValue, (1...10).contains(limit) else { throw LocalAgentError.invalidState }
            object = try memoryResult(notes: model.memories, query: query, limit: Int(limit))
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

    /// Production sessions use this entry point so large imported libraries do
    /// not block MainActor. The immutable snapshot remains consistent during read.
    static func executeAsync(name: String, arguments: MCPJSONValue, model: AppModel,
                             resultByteLimit: Int? = nil, trustedGoal: String? = nil,
                             authorizedConversationIDs: Set<UUID> = [], reviewedPlan: LocalReadPlan? = nil) async throws -> String {
        guard name == "search_memory" else {
            return try execute(name: name, arguments: arguments, model: model, resultByteLimit: resultByteLimit,
                               trustedGoal: trustedGoal, authorizedConversationIDs: authorizedConversationIDs, reviewedPlan: reviewedPlan)
        }
        guard let args = arguments.objectValue, Set(args.keys) == Set(["query", "limit"]),
              let query = args["query"]?.stringValue, let limit = args["limit"]?.integerValue,
              (1...10).contains(limit) else { throw LocalAgentError.invalidState }
        let notes = model.memories
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try memoryResult(notes: notes, query: query, limit: Int(limit))
        }
        let object = try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: { task.cancel() }
        let data: Data
        if let resultByteLimit {
            data = try LocalToolResultBudget.encode(object, collection: "memories", maximumBytes: resultByteLimit)
        } else { data = try object.encoded(maximumBytes: 16_384) }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func memoryResult(notes: [MemoryNote], query: String, limit: Int) throws -> MCPJSONValue {
        let result = try MemorySearch.phrase(notes, query: query, limit: limit)
        let memories = result.notes.map { note in
            MCPJSONValue.object(["id": .string(note.id.uuidString),
                "excerpt": .string(LocalSearchExcerpt.excerpt(text: note.content, query: query)),
                "excerptMayBeTruncated": .bool(note.content.utf8.count > 160)])
        }
        return .object(["memories": .array(memories),
            "totalMatchesInWindow": .integer(Int64(result.matchCount)),
            "resultsLimited": .bool(result.matchCount > limit),
            "searchedMemories": .integer(Int64(result.scannedCount)),
            "searchLimited": .bool(false)])
    }
}
