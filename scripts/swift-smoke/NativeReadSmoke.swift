import Foundation

@main struct NativeReadSmoke {
    static func main() async {
        do { try await run() } catch { print("FAIL: \(error)"); exit(1) }
    }
    static func run() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let engine = LlamaEngine()
        var request = GenerationRequest(messages: [ChatMessage(role: .user, content: "Read the app identity and installed models.")], systemPrompt: "", maxTokens: 256, temperature: 0)
        request.nativeReadGoal = request.messages[0].content
        let initial = try await engine.stream(request, modelURL: url)
        do { _ = try await engine.stream(request, modelURL: url); fatalError("Concurrent engine request admitted") }
        catch LocalModelError.busy { print("PASS shared engine admission") }
        var text = ""
        for try await part in initial { text += part }
        let proposal = try NativeReadProposal.parse(text)
        guard proposal.appInfo && proposal.installedModels else { fatalError("Missing requested reads") }
        print("PASS actual production actor native proposal \(text)")
        let cancelled = try await engine.stream(request, modelURL: url)
        try await Task.sleep(for: .milliseconds(50))
        await engine.unload()
        do { for try await _ in cancelled { }; fatalError("Unload did not cancel") }
        catch is CancellationError { print("PASS native cancellation and unload join") }
        var second = ""
        for try await part in try await engine.stream(request, modelURL: url) { second += part }
        _ = try NativeReadProposal.parse(second)
        print("PASS native reload after unload")
        request.nativeReadGoal = nil
        request.conciseQwen3 = true
        request = GenerationRequest(messages: [ChatMessage(role: .user, content: "Say hello only.")], systemPrompt: "You are helpful.", maxTokens: 128, temperature: 0, conciseQwen3: true)
        var chat = ""
        for try await part in try await engine.stream(request, modelURL: url) { chat += part }
        guard chat.lowercased().contains("hello") else { fatalError("Normal chat failed: \(chat)") }
        print("PASS normal chat after native generation: \(chat)")
        await engine.unload()
    }
}
