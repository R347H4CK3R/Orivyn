import Foundation
import llama

/// Synthetic-only Linux host. Production provider/engine/grammar/dispatcher;
/// AppModel storage scaffold is not iOS UI or SQLite verification.
@MainActor final class AppModel {
    var conversations: [Conversation] = []
    var installedModels: [LocalModelDescriptor] = []
    var memories: [MemoryNote] = []
}
private actor NormalSmokeJournal {
    var requests = 0
    var events: [NormalChatReadEvent] = []
    let url: URL
    init(url: URL) { self.url = url }
    func request(_ request: GenerationRequest) {
        requests += 1
        print("REQUEST \(requests) plain=\(request.normalChatAnswer) required=\(request.normalChatRequiredTool ?? "none") maxTokens=\(request.maxTokens)")
    }
    func record(_ event: NormalChatReadEvent) throws {
        events.append(event)
        try events.map { try $0.rendered() }.joined().write(to: url, atomically: true, encoding: .utf8)
        print("RECEIPT \(event.phase.rawValue) \(event.action.name)")
    }
    func snapshot() -> [NormalChatReadEvent] { events }
}
private struct ActualNormalModel: AIProvider {
    let id = "actual-llama", displayName = "Actual pinned model"
    let engine: LlamaEngine
    let url: URL
    let journal: NormalSmokeJournal
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        await journal.request(request)
        var raw = ""
        for try await token in try await engine.stream(request, modelURL: url) { raw += token }
        print("RAW plain=\(request.normalChatAnswer) \(raw)")
        return AsyncThrowingStream { $0.yield(raw); $0.finish() }
    }
}
@main struct NormalChatAgentSmoke {
    enum Failure: Error { case failed(String) }
    @MainActor static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Normal chat smoke failed: \(error)\n".utf8)); exit(1) }
    }
    @MainActor static func run() async throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.failed("Explicit pinned model/runtime required") }
        CommandLine.arguments[2].withCString { ggml_backend_load_all_from_path($0) }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let model = AppModel(), engine = LlamaEngine()
        let marker = "cedar-" + UUID().uuidString.lowercased()
        model.memories = [.init(content: "Cedar acceptance verification marker: \(marker).")]
        let generic = "Can you build me a simple python script"
        let refusal = [ChatMessage(role: .user, content: "Make me an unsigned iOS app"),
                       ChatMessage(role: .assistant, content: "I’m unable to build or modify executable files or apps outside the Orivyn app.")]
        let long: [ChatMessage] = (0..<6).map { index in
            ChatMessage(role: index % 2 == 0 ? .user : .assistant, content: (0..<12).map { _ in UUID().uuidString }.joined(separator: " "))
        }
        let exactRefusals = [
            ChatMessage(role: .user, content: "Expand your capabilities"),
            ChatMessage(role: .assistant, content: "My capabilities are limited to assisting with app-related tasks within Orivyn."),
            ChatMessage(role: .user, content: generic),
            ChatMessage(role: .assistant, content: "I’m unable to build or modify executable files or apps outside the Orivyn app."),
            ChatMessage(role: .user, content: generic),
            ChatMessage(role: .assistant, content: "I’m unable to build or modify executable files or apps outside the Orivyn app.")]
        let followup = [
            ChatMessage(role: .user, content: "Can you make an exact replica of Samsung DeX for iPhone with macOS as the desktop and USB C to HDMI?"),
            ChatMessage(role: .assistant, content: "Sorry, I can't assist with that."),
            ChatMessage(role: .user, content: "Why not"),
            ChatMessage(role: .assistant, content: "I'm not able to assist with that.")]
        let cases: [(String, String, [ChatMessage], String?)] = [
            ("fresh", generic, [], nil), ("refusal", generic, refusal, nil),
            ("long", generic, long, nil), ("multi-refusal", generic, exactRefusals, nil),
            ("followup", "Explain", followup, nil), ("calculate", "Calculate 173 * 29 - 41", [], "calculate"),
            ("memory", "Look through my saved notes for Cedar acceptance and tell me the exact verification marker stored there.", [], "search_memory"),
            ("appinfo", "Read get_app_info now and explain what this app can actually do.", long, "get_app_info")]
        let selection = ProcessInfo.processInfo.environment["ORIVYN_NORMAL_CASE"]
        for (label, goal, history, expectedTool) in cases where selection == nil || selection == label {
            let journal = NormalSmokeJournal(url: root.appendingPathComponent(label + "-receipts.txt"))
            let actual = ActualNormalModel(engine: engine, url: url, journal: journal)
            guard let turn = NormalChatLocalTurn(goal: goal, hasAttachments: false, isExternalDraft: false) else { throw Failure.failed("Admission") }
            let provider = NormalChatLocalAgentProvider(turn: turn, model: actual,
                validateContext: { try Task.checkCancellation() }, read: { action in
                    try await LocalReadTools.executeAsync(name: action.name, arguments: action.arguments, model: model,
                        resultByteLimit: 4096, trustedGoal: goal)
                }, record: { try await journal.record($0) }, deadline: .now.advanced(by: .seconds(600)))
            var answer = ""
            do {
                for try await token in try await provider.stream(.init(messages: history + [.init(role: .user, content: goal)], systemPrompt: "")) { answer += token }
            } catch {
                try "\(error)".write(to: root.appendingPathComponent(label + "-error.txt"), atomically: true, encoding: .utf8)
                await engine.unload(); throw error
            }
            try answer.write(to: root.appendingPathComponent(label + "-answer.txt"), atomically: true, encoding: .utf8)
            let events = await journal.snapshot(), successes = events.filter { $0.phase == .succeeded }
            if let expectedTool {
                guard successes.count == 1, successes[0].action.name == expectedTool else { throw Failure.failed("\(label): exactly one required read missing") }
                if label == "memory", !answer.contains(marker) { throw Failure.failed("Memory answer not grounded") }
                if label == "calculate", !answer.contains("4976") { throw Failure.failed("Wrong calculation") }
                if label == "appinfo" {
                    guard let recorded = successes.first?.result,
                          answer == (try AppSelfKnowledge.renderRecordedResult(recorded)),
                          answer.contains("Not available:"), answer.contains("self-repair"),
                          answer.contains("additional capabilities omitted") else { throw Failure.failed("App-info status rendering differs from recorded metadata") }
                    let payload = NormalChatPrompt(policy: "", goal: String(repeating: "test ", count: 800), history: [],
                        evidence: [.object(["tool": .string("get_app_info"), "result": .string(recorded)])], plainAnswer: true)
                    var request = GenerationRequest(messages: [.init(role: .user, content: try payload.render(history: [], omitted: 0))],
                        systemPrompt: "Untrusted reference data. No tools execute.", maxTokens: 1024, temperature: 0, conciseQwen3: true)
                    request.normalChatPrompt = payload; request.normalChatAnswer = true
                    var rejected = false
                    do { for try await _ in try await engine.stream(request, modelURL: url) {} }
                    catch ProviderError.rejected(let reason) { rejected = reason.contains("current request and recorded results") }
                    guard rejected else { throw Failure.failed("Real tokenizer accepted irreducible oversized goal+evidence") }
                    print("PASS actual-tokenizer post-app-info stress rejected without replay")
                }
            } else if label == "followup" {
                guard events.isEmpty, ["iphone", "ios", "macos"].contains(where: { answer.lowercased().contains($0) }),
                      !answer.lowercased().contains("explain is a verb") else { throw Failure.failed("Follow-up lost referent") }
            } else {
                guard events.isEmpty, answer.range(of: #"(?s)(?:print\s*\(|def\s+\w+\s*\(|```python)"#, options: .regularExpression) != nil else { throw Failure.failed("\(label): usable code absent or irrelevant read") }
            }
            let display = answer.components(separatedBy: "App-recorded receipts above describe actual local operations.]\n").last ?? answer
            guard !display.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else { throw Failure.failed("Unrequested JSON answer wrapper") }
            guard !answer.contains("<think>"), !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.failed("Visible output invalid") }
            print("PASS \(label): \(answer)")
        }
        await engine.unload()
    }
}
