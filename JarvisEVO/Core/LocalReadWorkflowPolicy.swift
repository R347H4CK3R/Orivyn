import Foundation

/// Independent native prerequisite/source guard. No model decision can grant scope.
struct LocalReadWorkflowPolicy: Equatable, Sendable {
    struct Action: Codable, Equatable, Sendable {
        let name: String
        let arguments: MCPJSONValue
        var decision: MCPJSONValue { .object(["type":.string("tool"),"name":.string(name),"arguments":arguments]) }
    }
    let actions: [Action]
    let canAnswer: Bool
    private struct Progress { let messageID: String; let role: String; let bytes: Int; var text: String; var done: Bool }

    static func fullTitleMatchIDs(matches: [MCPJSONValue], title: String, conversations: [Conversation]) throws -> [String] {
        var found: [String] = []
        for match in matches {
            guard let raw=match.objectValue?["id"]?.stringValue, let id=UUID(uuidString:raw),
                  let current=conversations.first(where:{$0.id==id}) else { throw LocalAgentError.invalidState }
            if LocalReadPlan.canonicalTitle(current.title)==LocalReadPlan.canonicalTitle(title) { found.append(id.uuidString.lowercased()) }
        }
        guard Set(found).count==found.count else { throw LocalAgentError.invalidState }
        return found.sorted()
    }
    static func derive(plan: LocalReadPlan, history: [LocalAgentSnapshot.Event], conversations: [Conversation]) throws -> Self {
        guard history.count <= 6 else { throw LocalAgentError.invalidState }
        var actions = [Action(name:"search_conversations",arguments:.object(["query":.string(plan.query),"limit":.integer(10)]))]
        var complete = false, selected: UUID?
        var progress: [Int:Progress] = [:]
        for event in history {
            guard event.outcome == "succeeded", let raw = event.result,
                  actions.contains(Action(name:event.name,arguments:event.arguments)),
                  let result = try MCPJSONValue.parse(Data(raw.utf8),maximumBytes:4096).objectValue else { throw LocalAgentError.invalidState }
            if event.name == "search_conversations" {
                guard try LocalReviewedSearch.result(plan:plan,conversations:conversations) == .object(result) else { throw LocalAgentError.invalidState }
                guard let matches = result["matches"]?.arrayValue else { throw LocalAgentError.invalidState }
                if plan.kind == "conversation_search" { actions=[]; complete=true; continue }
                guard result["resultsLimited"]?.boolValue == false, result["searchLimited"]?.boolValue == false,
                      result["resultTruncated"]?.boolValue != true, let title=plan.title else { throw LocalAgentError.invalidState }
                let targets = try fullTitleMatchIDs(matches:matches,title:title,conversations:conversations)
                guard let recorded=result["approvedTitleMatchIDs"]?.arrayValue,
                      recorded==targets.map({ .string($0) }), targets.count==1,
                      let id=UUID(uuidString:targets[0]) else { throw LocalAgentError.invalidState }
                selected=id
            } else {
                guard let selected, let index=event.arguments.objectValue?["messageIndex"]?.integerValue,
                      let offset=event.arguments.objectValue?["offset"]?.integerValue,
                      let text=result["text"]?.stringValue, let total=result["messageBytes"]?.integerValue,
                      let mid=result["messageID"]?.stringValue, let role=result["role"]?.stringValue,
                      result["state"]?.stringValue == "complete" else { throw LocalAgentError.invalidState }
                // Recreate every saved page from current actual messages. This checks
                // IDs, role, state, cursor, content, size, attachment metadata and next.
                let current = try LocalConversationRead.read(conversations:conversations,arguments:event.arguments,authorizedIDs:[selected])
                guard current == .object(result) else { throw LocalAgentError.invalidState }
                let old=progress[Int(index)]
                guard old == nil || (old?.messageID==mid && old?.role==role && old?.bytes==Int(total)),
                      Int(offset)==old?.text.utf8.count ?? 0 else { throw LocalAgentError.invalidState }
                let joined=(old?.text ?? "")+text, done=joined.utf8.count==total
                guard joined.utf8.count <= total, done || !text.isEmpty else { throw LocalAgentError.invalidState }
                if done {
                    guard let conversation=conversations.first(where:{$0.id==selected}), conversation.messages.indices.contains(Int(index)),
                          conversation.messages[Int(index)].content==joined else { throw LocalAgentError.invalidState }
                }
                progress[Int(index)] = Progress(messageID:mid,role:role,bytes:Int(total),text:joined,done:done)
            }
            guard let selected, let indexes=plan.messageIndexes else { throw LocalAgentError.invalidState }
            actions=indexes.filter { progress[$0]?.done != true }.map { Action(name:"read_conversation",arguments:.object(["id":.string(selected.uuidString.lowercased()),"messageIndex":.integer(Int64($0)),"offset":.integer(Int64(progress[$0]?.text.utf8.count ?? 0))])) }
            complete=actions.isEmpty
        }
        if let selected, let title=plan.title {
            let current=conversations.filter { LocalReadPlan.canonicalTitle($0.title)==LocalReadPlan.canonicalTitle(title) }
            guard current.count==1,current[0].id==selected else { throw LocalAgentError.invalidState }
        }
        guard complete || history.count < 6 else { throw LocalAgentError.invalidState }
        return Self(actions:actions,canAnswer:complete)
    }
    func validate(_ intent: LocalAgentSnapshot.Intent) throws {
        guard actions.contains(Action(name:intent.name,arguments:intent.arguments)) else { throw LocalAgentError.invalidState }
    }
}
