import Foundation

@main struct NativeReadSmoke {
    static func main() async {
        do { try await run() } catch { print("FAIL: \(error)"); exit(1) }
    }
    static func run() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let policy = NativeReadPolicy(rawValue: UInt32(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "1")!)!
        guard NativeReadProposal.policy(forVerifiedSHA256: NativeReadProposal.admittedModelSHA256) == .q8,
              NativeReadProposal.policy(forVerifiedSHA256: NativeReadProposal.candidateQ4SHA256) == .q4Candidate,
              NativeReadProposal.policy(forVerifiedSHA256: String(repeating: "0", count: 64)) == nil,
              NativeReadProposal.policy(forVerifiedSHA256: NativeReadProposal.candidateQ4SHA256.uppercased()) == nil else { fatalError("Policy hash mapping") }
        print("PASS exact verified hash policy mapping")
        let engine = LlamaEngine()
        var request = GenerationRequest(messages: [ChatMessage(role: .user, content: "Read the app identity and installed models.")], systemPrompt: "", maxTokens: 256, temperature: 0)
        request.nativeReadGoal = request.messages[0].content
        do { _ = try await engine.stream(request, modelURL: url); fatalError("Missing policy admitted") }
        catch LocalModelError.invalidRequest { print("PASS missing native policy rejected before worker") }
        let initial = try await engine.stream(request, modelURL: url, nativeReadPolicy: policy)
        do { _ = try await engine.stream(request, modelURL: url, nativeReadPolicy: policy); fatalError("Concurrent engine request admitted") }
        catch LocalModelError.busy { print("PASS shared engine admission") }
        var text = ""
        for try await part in initial { text += part }
        let proposal = try NativeReadProposal.parse(text)
        guard proposal.appInfo && proposal.installedModels else { fatalError("Missing requested reads") }
        print("PASS actual production actor native proposal \(text)")
        let cancelled = try await engine.stream(request, modelURL: url, nativeReadPolicy: policy)
        try await Task.sleep(for: .milliseconds(50))
        await engine.unload()
        do { for try await _ in cancelled { }; fatalError("Unload did not cancel") }
        catch is CancellationError { print("PASS native cancellation and unload join") }
        var second = ""
        for try await part in try await engine.stream(request, modelURL: url, nativeReadPolicy: policy) { second += part }
        _ = try NativeReadProposal.parse(second)
        print("PASS native reload after unload")
        request.nativeReadGoal = nil
        request.conciseQwen3 = true
        request = GenerationRequest(messages: [ChatMessage(role: .user, content: "Say hello only.")], systemPrompt: "You are helpful.", maxTokens: 128, temperature: 0, conciseQwen3: true)
        do { _ = try await engine.stream(request, modelURL: url, nativeReadPolicy: policy); fatalError("Extra native policy admitted") }
        catch LocalModelError.invalidRequest { print("PASS extra native policy rejected before worker") }
        var chat = ""
        for try await part in try await engine.stream(request, modelURL: url) { chat += part }
        guard chat.lowercased().contains("hello") else { fatalError("Normal chat failed: \(chat)") }
        print("PASS normal chat after native generation: \(chat)")
        await engine.unload()
    }
}
