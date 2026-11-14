import Foundation
import llama

@main struct QwenModeSmoke {
    enum Failure: Error { case failed(String) }
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Qwen mode failed: \(error)\n".utf8)); exit(1) }
    }
    static func run() async throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.failed("Arguments missing") }
        CommandLine.arguments[2].withCString { ggml_backend_load_all_from_path($0) }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()
        let engine = LlamaEngine()
        do {
            for name in ["Qwen3-0.6B-Q8_0.gguf", "Qwen3-1.7B-Q8_0.gguf"] {
                for concise in [false, true, false] {
                    var request = GenerationRequest(messages: [ChatMessage(role: .user, content: "Reply with just the word hello.")], systemPrompt: "Follow the user's request briefly.", maxTokens: 256, temperature: 0)
                    request.conciseQwen3 = concise
                    var text = ""
                    for try await part in try await engine.stream(request, modelURL: folder.appendingPathComponent(name)) { text += part }
                    let hasThinking = text.contains("<think>") || text.contains("</think>")
                    guard text.lowercased().contains("hello"), hasThinking != concise else {
                        throw Failure.failed("\(name) concise=\(concise): \(text)")
                    }
                    print("PASS \(name) concise=\(concise), raw output: \(text)")
                }
                await engine.unload()
            }
            var otherOutputs: [String] = []
            for concise in [false, true] {
                var request = GenerationRequest(messages: [ChatMessage(role: .user, content: "Reply with just the word hello.")], systemPrompt: "Follow the user's request briefly.", maxTokens: 64, temperature: 0)
                request.conciseQwen3 = concise
                var text = ""
                for try await part in try await engine.stream(request, modelURL: URL(fileURLWithPath: CommandLine.arguments[1])) { text += part }
                otherOutputs.append(text)
            }
            guard otherOutputs.count == 2, otherOutputs[0] == otherOutputs[1] else { throw Failure.failed("Other architecture changed") }
            await engine.unload()
            print("PASS non-Qwen3 architecture unaffected by concise option")
        } catch { await engine.unload(); throw error }
    }
}
