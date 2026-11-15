import Foundation
import llama

/// Synthetic history only. Uses the actual Swift engine/grammar/dispatcher and JS
/// reducer; AppModel and the JavaScriptCore boundary are Linux host scaffolds.
@MainActor final class AppModel {
    var conversations: [Conversation] = []
    var installedModels: [LocalModelDescriptor] = []
    var memories: [MemoryNote] = []
}
@main struct ReviewedConversationAgentSmoke {
    enum Failure: Error { case failed(String) }
    @MainActor static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Conversation agent failed: \(error)\n".utf8)); exit(1) }
    }
    static func core(_ method: String, _ arguments: [String]) throws -> String {
        let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let process = Process()
        guard let node = ProcessInfo.processInfo.environment["ORIVYN_TEST_NODE"] else { throw Failure.failed("Explicit Node runtime missing") }
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [directory.appendingPathComponent("CalculatorAgentCore.cjs").path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output
        try process.run()
        let data = try JSONSerialization.data(withJSONObject: ["method": method, "args": arguments])
        input.fileHandleForWriting.write(data)
        try input.fileHandleForWriting.close()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.failed("Production reducer rejected \(method)") }
        return try JSONDecoder().decode(String.self, from: result)
    }
    @MainActor static func run() async throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.failed("Arguments missing") }
        CommandLine.arguments[2].withCString { ggml_backend_load_all_from_path($0) }
        let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let store = try LocalAgentStore(directory: root.appendingPathComponent("agent-records"))
        let model = AppModel(), fixtureID = UUID(uuidString: "abcdefab-1234-1234-1234-123456789abc")!
        let variant = ProcessInfo.processInfo.environment["ORIVYN_CONVERSATION_FIXTURE"]
        let alternate = variant == "maple"
        let pagination = variant == "pagination"
        let quotedTitle = variant == "quoted-title"
        let independentQuoted = variant == "independent-quoted"
        let independentUnquoted = variant == "independent-unquoted"
        let title = independentQuoted ? "Conversation about Q2" : (independentUnquoted ? "Moss-trail 27" : (quotedTitle ? "Willow conversation" : (pagination ? "Juniper pages" : (alternate ? "Maple journal" : "Orchid notebook"))))
        let marker = (independentQuoted || independentUnquoted) ? "HOLDOUT-" + UUID().uuidString : quotedTitle ? "QUOTE-" + UUID().uuidString : (pagination ? "PAGE-" + UUID().uuidString : (alternate ? "HARBOR-319" : "LANTERN-742"))
        let padding = pagination ? String(repeating:"Background notes. ", count:34) : ""
        model.conversations = [Conversation(id: fixtureID, title: title, messages: [
            ChatMessage(role: .user, content: "\(title) opening note. The exact verification code is recorded in the second message, not this note."),
            ChatMessage(role: .assistant, content: padding + "The synthetic verification code is \(marker). This is harmless test fixture text.")]),
            Conversation(title: "Unrelated notebook", messages: [ChatMessage(role: .user, content: "No requested information here.")])]
        let id = UUID().uuidString.lowercased()
        let goal = independentQuoted ? "Read message 2 of the conversation titled \"Conversation about Q2\" and return only its verification code." : quotedTitle ? "Read message 2 of the conversation titled \"Willow conversation\" and return only its verification code." : (pagination ? "Return only the exact code, with no label or explanation. " : "") + "Find the saved \(title) conversation, read its second message, and tell me the exact verification code. Search first, then use read_conversation. Do not guess from a search excerpt."
        let engine = LlamaEngine()
        let proposalRequest=try GenerationRequest.readPlanProposal(goal:goal,kind:"conversation_read")
        try Data(proposalRequest.messages[0].content.utf8).write(to:root.appendingPathComponent("proposal-prompt.txt"))
        var proposalText=""
        do {
            for try await part in try await engine.stream(proposalRequest,modelURL:modelURL) {
                guard proposalText.utf8.count+part.utf8.count<=4096 else { throw Failure.failed("Proposal output bound") }
                proposalText += part
                try Data(proposalText.utf8).write(to:root.appendingPathComponent("proposal-raw.json"))
            }
        } catch { await engine.unload(); throw error }
        let plan=try LocalReadPlan.parseProposal(proposalText)
        // Synthetic explicit-review oracle. Never repair or replace a model plan.
        guard plan.kind=="conversation_read",plan.title==title,plan.messageIndexes==[1],
              [title,title.components(separatedBy:" ")[0]].contains(plan.query) else {
            await engine.unload(); throw Failure.failed("Actual model proposal did not match fixture intent; not approved")
        }
        let approved:MCPJSONValue = .object(["goal":.string(goal),"id":.string(id),"plan":try MCPJSONValue.parse(Data(plan.encoded().utf8))])
        var state=try core("createReviewed",[String(decoding:approved.encoded(),as:UTF8.self)])
        try store.save(state,id:id)
        do {
            for cycle in 0..<108 {
                let item = try JSONDecoder().decode(LocalAgentSnapshot.self, from: Data(state.utf8))
                guard item.status == "ready" else { throw Failure.failed("Unexpected terminal state: \(item.status)") }
                let prompt = try core("prompt", [try store.load(id: id)])
                try Data(prompt.utf8).write(to: root.appendingPathComponent("prompt-\(cycle).txt"))
                guard prompt.utf8.count <= 3500,
                      let evidenceLine = prompt.components(separatedBy: "\n").first(where: { $0.hasPrefix("UNTRUSTED_RESULTS_JSON=") }),
                      let evidence = try MCPJSONValue.parse(Data(evidenceLine.dropFirst("UNTRUSTED_RESULTS_JSON=".count).utf8)).arrayValue else {
                    throw Failure.failed("Complete current evidence missing from bounded prompt")
                }
                let successful = item.history.filter { $0.outcome == "succeeded" }
                guard evidence.count == successful.count,
                      zip(evidence, successful).allSatisfy({ $0.0.objectValue?["result"]?.stringValue == $0.1.result }) else {
                    throw Failure.failed("A prior result was omitted from the current inference context")
                }
                let policy=try LocalReadWorkflowPolicy.derive(plan:plan,history:item.history,conversations:model.conversations)
                let request=GenerationRequest.reviewedAgent(prompt:prompt,policy:policy)
                try Data(LocalAgentGrammar.reviewed(policy).utf8).write(to:root.appendingPathComponent("grammar-\(cycle).gbnf"))
                let requestEvidence: [String: Any] = ["maxTokens": request.maxTokens, "temperature": request.temperature,
                    "reviewedWorkflow": true, "canAnswer": policy.canAnswer, "conciseQwen3": request.conciseQwen3,
                    "conversationIDs": request.localAgentConversationIDs, "factory": "GenerationRequest.reviewedAgent", "grammar": "bundled production LocalAgentDecision.gbnf"]
                try JSONSerialization.data(withJSONObject: requestEvidence, options: [.sortedKeys]).write(to: root.appendingPathComponent("request-\(cycle).json"))
                var decision = ""
                for try await part in try await engine.stream(request, modelURL: modelURL) {
                    guard decision.utf8.count + part.utf8.count <= 32_768 else { throw Failure.failed("Output bound") }
                    decision += part
                    try Data(decision.utf8).write(to: root.appendingPathComponent("decision-\(cycle).json"))
                }
                print("ACTUAL MODEL DECISION [\(cycle)]: \(decision)")
                state = try core("acceptDecision", [state, decision])
                let accepted = try JSONDecoder().decode(LocalAgentSnapshot.self, from: Data(state.utf8))
                if accepted.status == "answered" {
                    guard try LocalReadWorkflowPolicy.derive(plan:plan,history:accepted.history,conversations:model.conversations).canAnswer else { throw Failure.failed("Native answer guard") }
                }
                try store.save(state, id: id) // Native answer validation precedes persistence; pending calls remain durable before dispatch.
                if accepted.status == "answered" {
                    guard accepted.history.contains(where: { $0.name == "search_conversations" && $0.outcome == "succeeded" }),
                          accepted.history.contains(where: { $0.name == "read_conversation" && $0.outcome == "succeeded" && $0.result?.contains(marker) == true }),
                          !accepted.history.contains(where: { $0.name == "search_conversations" && $0.result?.contains(marker) == true }),
                          let answer = accepted.answer, answer.contains(marker) else { throw Failure.failed("Answer lacked actual search/read evidence or exact fixture code") }
                    if pagination {
                        guard answer == marker,
                              accepted.history.contains(where: { $0.name == "read_conversation" && ($0.arguments.objectValue?["offset"]?.integerValue ?? 0) > 0 }) else {
                            throw Failure.failed("Paginated exact-answer acceptance failed; extra wording or missing page")
                        }
                    }
                    let reopened = try LocalAgentStore(directory: root.appendingPathComponent("agent-records"))
                    guard try reopened.load(id: id) == state else { throw Failure.failed("Final state did not reopen") }
                    try Data(state.utf8).write(to: root.appendingPathComponent("FINAL-STATE.json"))
                    print("PASS real model search -> authorized conversation read -> required fixture answer check, persisted and reopened")
                    await engine.unload(); return
                }
                if accepted.status == "ready" { continue } // Real reducer result paging, not a fake native call.
                guard accepted.status == "running", let pending = accepted.pending else { throw Failure.failed("Stopped at reducer limit: \(accepted.status)") }
                try LocalReadWorkflowPolicy.derive(plan:plan,history:accepted.history,conversations:model.conversations).validate(pending)
                let result = try LocalReadTools.execute(name: pending.name, arguments: pending.arguments, model: model,
                    resultByteLimit: 4096, trustedGoal: goal, authorizedConversationIDs: LocalConversationRead.authorizedIDs(history: accepted.history),reviewedPlan:plan)
                try Data(result.utf8).write(to: root.appendingPathComponent("result-\(accepted.steps).json"))
                let encoded = try MCPJSONValue.object(["operationID": .string(pending.operationID), "result": .string(result)]).encoded(maximumBytes: 32_768)
                state = try core("recordResult", [state, String(decoding: encoded, as: UTF8.self)])
                try store.save(state, id: id)
            }
            throw Failure.failed("Diagnostic cycle bound reached without answer")
        } catch {
            try? Data(state.utf8).write(to: root.appendingPathComponent("STOPPED-STATE.json"))
            await engine.unload(); throw error
        }
    }
}
