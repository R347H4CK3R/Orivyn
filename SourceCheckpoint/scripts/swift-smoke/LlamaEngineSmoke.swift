import Foundation
import llama

/// Actual production Swift actor and actual GGUF inference. No provider doubles.
@main struct LlamaEngineSmoke {
    enum Failure: Error { case failed(String) }
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Smoke failed: \(error)\n".utf8)); exit(1) }
    }
    static func run() async throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.failed("Explicit local GGUF required") }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        // Linux release backends are separate shared objects, unlike Apple's
        // linked framework. This is explicit host setup, not production engine code.
        CommandLine.arguments[2].withCString { ggml_backend_load_all_from_path($0) }
        let engine = LlamaEngine()
        do {
            let request = GenerationRequest(messages: [ChatMessage(role: .user, content: "Reply with just the word hello.")], systemPrompt: "Follow the user's request briefly.", maxTokens: 64, temperature: 0)
            let stream = try await engine.stream(request, modelURL: url)
            var reply = ""
            for try await part in stream { reply += part }
            guard reply.lowercased().contains("hello") else { throw Failure.failed("Unexpected actual reply: \(reply)") }
            print("PASS actual production actor inference completed: \(reply)")
            var invalid = request; invalid.maxTokens = 0
            do { _ = try await engine.stream(invalid, modelURL: url); throw Failure.failed("Invalid request accepted") }
            catch LocalModelError.invalidRequest { print("PASS invalid request rejected") }

            let limited = GenerationRequest(messages: [ChatMessage(role: .user, content: "Write a long story about a traveler.")], systemPrompt: request.systemPrompt, maxTokens: 1, temperature: 0)
            let limitedStream = try await engine.stream(limited, modelURL: url)
            do {
                for try await _ in limitedStream { }
                throw Failure.failed("Token-limited reply falsely completed")
            } catch LocalModelError.generationLimitReached { print("PASS token limit reports incomplete generation") }

            var long = limited; long.maxTokens = 512
            let active = try await engine.stream(long, modelURL: url)
            do { _ = try await engine.stream(request, modelURL: url); throw Failure.failed("Concurrent admission accepted") }
            catch LocalModelError.busy { print("PASS busy generation rejects second request") }
            await engine.unload()
            do {
                for try await _ in active { }
                throw Failure.failed("Unload did not cancel owned generation")
            } catch is CancellationError { print("PASS unload cancels and joins active generation") }
            let reloaded = try await engine.stream(request, modelURL: url)
            var next = ""
            for try await part in reloaded { next += part }
            guard next.lowercased().contains("hello") else { throw Failure.failed("Reload reply: \(next)") }
            print("PASS generation succeeds after resource release: \(next)")
            await engine.unload()
        } catch {
            await engine.unload()
            throw error
        }
    }
}
