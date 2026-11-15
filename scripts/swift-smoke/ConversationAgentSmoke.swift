import Foundation
import llama

/// Synthetic history only. Uses the actual Swift engine/grammar/dispatcher and JS
/// reducer; AppModel and the JavaScriptCore boundary are Linux host scaffolds.
@MainActor final class AppModel {
    var conversations: [Conversation] = []
    var installedModels: [LocalModelDescriptor] = []
    var memories: [MemoryNote] = []
}
@main struct ConversationAgentSmoke {
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
        let alternate = ProcessInfo.processInfo.environment["ORIVYN_CONVERSATION_FIXTURE"] == "maple"
        let title = alternate ? "Maple journal" : "Orchid notebook"
        let marker = alternate ? "HARBOR-319" : "LANTERN-742"
        model.conversations = [Conversation(id: fixtureID, title: title, messages: [
            ChatMessage(role: .user, content: "\(title) opening note. The exact verification code is recorded in the second message, not this note."),
            ChatMessage(role: .assistant, content: "The synthetic verification code is \(marker). This is harmless test fixture text.")]),
            Conversation(title: "Unrelated notebook", messages: [ChatMessage(role: .user, content: "No requested information here.")])]
        let id = UUID().uuidString.lowercased()
        let goal = "Find the saved \(title) conversation, read its second message, and tell me the exact verification code. Search first, then use read_conversation. Do not guess from a search excerpt."
        var state = try core("create", [goal, id])
        try store.save(state, id: id)
        let engine = LlamaEngine()
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
                let conversationIDs = try JSONDecoder().decode([String].self, from: Data(core("conversationIDs", [state]).utf8))
                let request = GenerationRequest.localAgent(prompt: prompt,
                    requiresTool: !item.history.contains { $0.outcome == "succeeded" }, conversationIDs: conversationIDs)
                let requestEvidence: [String: Any] = ["maxTokens": request.maxTokens, "temperature": request.temperature,
                    "localAgentRequiresTool": request.localAgentRequiresTool!, "conciseQwen3": request.conciseQwen3,
                    "conversationIDs": request.localAgentConversationIDs, "factory": "GenerationRequest.localAgent", "grammar": "bundled production LocalAgentDecision.gbnf"]
                try JSONSerialization.data(withJSONObject: requestEvidence, options: [.sortedKeys]).write(to: root.appendingPathComponent("request-\(cycle).json"))
                var decision = ""
                for try await part in try await engine.stream(request, modelURL: modelURL) {
                    guard decision.utf8.count + part.utf8.count <= 32_768 else { throw Failure.failed("Output bound") }
                    decision += part
                    try Data(decision.utf8).write(to: root.appendingPathComponent("decision-\(cycle).json"))
                }
                print("ACTUAL MODEL DECISION [\(cycle)]: \(decision)")
                state = try core("acceptDecision", [state, decision])
                try store.save(state, id: id) // Actual durable marker before every dispatcher read.
                let accepted = try JSONDecoder().decode(LocalAgentSnapshot.self, from: Data(state.utf8))
                if accepted.status == "answered" {
                    guard accepted.history.contains(where: { $0.name == "search_conversations" && $0.outcome == "succeeded" }),
                          accepted.history.contains(where: { $0.name == "read_conversation" && $0.outcome == "succeeded" && $0.result?.contains(marker) == true }),
                          !accepted.history.contains(where: { $0.name == "search_conversations" && $0.result?.contains(marker) == true }),
                          let answer = accepted.answer, answer.contains(marker) else { throw Failure.failed("Answer lacked actual search/read evidence or exact fixture code") }
                    let reopened = try LocalAgentStore(directory: root.appendingPathComponent("agent-records"))
                    guard try reopened.load(id: id) == state else { throw Failure.failed("Final state did not reopen") }
                    try Data(state.utf8).write(to: root.appendingPathComponent("FINAL-STATE.json"))
                    print("PASS real model search -> authorized conversation read -> exact fixture answer, persisted and reopened")
                    await engine.unload(); return
                }
                if accepted.status == "ready" { continue } // Real reducer result paging, not a fake native call.
                guard accepted.status == "running", let pending = accepted.pending else { throw Failure.failed("Stopped at reducer limit: \(accepted.status)") }
                let result = try LocalReadTools.execute(name: pending.name, arguments: pending.arguments, model: model,
                    resultByteLimit: 4096, trustedGoal: goal, authorizedConversationIDs: LocalConversationRead.authorizedIDs(history: accepted.history))
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
