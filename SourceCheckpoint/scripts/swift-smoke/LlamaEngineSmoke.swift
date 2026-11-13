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
            let oversized = GenerationRequest(messages: request.messages, systemPrompt: String(repeating: "safety ", count: 4096), maxTokens: 64, temperature: 0)
            do {
                let overflow = try await engine.stream(oversized, modelURL: url)
                for try await _ in overflow { }
                throw Failure.failed("Oversized system prompt accepted")
            } catch ProviderError.rejected(let reason) {
                guard reason.contains("Nothing was silently removed") else { throw Failure.failed("Unexpected rejection: \(reason)") }
                print("PASS actual tokenizer rejects oversized system prompt without silent truncation")
            }

            let absent = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".gguf")
            do {
                let missing = try await engine.stream(request, modelURL: absent)
                for try await _ in missing { }
                throw Failure.failed("Missing model accepted")
            } catch LocalModelError.loadFailed { print("PASS missing model reports load failure") }
            let recovered = try await engine.stream(request, modelURL: url)
            var recoveredText = ""
            for try await part in recovered { recoveredText += part }
            guard recoveredText.lowercased().contains("hello") else { throw Failure.failed("Recovery reply: \(recoveredText)") }
            print("PASS valid model reloads after failed model switch")
            for requireTool in [true, false] {
                var agent = GenerationRequest(messages: [ChatMessage(role: .user, content: requireTool ? "Call get_app_info with empty arguments now." : "Return an answer JSON with text hello.")], systemPrompt: "Return exactly one JSON decision, no commentary.", maxTokens: 128, temperature: 0)
                agent.localAgentRequiresTool = requireTool
                let result = try await engine.stream(agent, modelURL: url)
                var json = ""
                for try await part in result { json += part }
                guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                      let type = object["type"] as? String,
                      (requireTool ? type == "tool" : ["tool", "answer"].contains(type)) else {
                    throw Failure.failed("Grammar output invalid: \(json)")
                }
                if requireTool {
                    guard let name = object["name"] as? String,
                          ["get_app_info", "list_models", "search_conversations"].contains(name),
                          object["arguments"] is [String: Any] else {
                        throw Failure.failed("Required external tool grammar invalid: \(json)")
                    }
                }
                print("PASS actual grammar sampling requireTool=\(requireTool): \(json)")
            }
            await engine.unload()
            let fixture = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("replacement-fixture")
            let fm = FileManager.default
            try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: fixture) }
            let linked = fixture.appendingPathComponent("model.gguf")
            try fm.linkItem(at: url, to: linked)
            for try await _ in try await engine.stream(request, modelURL: linked) { }
            let replacement = fixture.appendingPathComponent("replacement")
            try Data("not a gguf".utf8).write(to: replacement)
            let renamed = replacement.path.withCString { source in
                linked.path.withCString { target in rename(source, target) }
            }
            guard renamed == 0 else { throw Failure.failed("Fixture replacement failed") }
            do {
                for try await _ in try await engine.stream(request, modelURL: linked) { }
                throw Failure.failed("Replaced model reused stale mapped bytes")
            } catch LocalModelError.loadFailed { print("PASS atomic same-path replacement invalidates model cache") }
            await engine.unload()
        } catch {
            await engine.unload()
            throw error
        }
    }
}
