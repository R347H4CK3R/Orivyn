import Foundation
import llama

/// Per-family completion check with real weights. No model output substitute.
@main struct CatalogInferenceSmoke {
    static func main() async {
        guard CommandLine.arguments.count == 3 else { exit(2) }
        CommandLine.arguments[2].withCString { ggml_backend_load_all_from_path($0) }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()
        let engine = LlamaEngine()
        var results: [[String: Any]] = []
        for entry in LocalModelCatalog.entries {
            let descriptor = entry.descriptor
            let url = folder.appendingPathComponent(descriptor.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                results.append(["model": descriptor.id, "status": "missing"]); continue
            }
            let started = Date()
            var text = ""
            var result: [String: Any] = ["model": descriptor.id, "file": descriptor.fileName]
            do {
                let request = GenerationRequest(messages: [ChatMessage(role: .user, content: "Reply with just the word hello.")], systemPrompt: "Follow the user's request briefly.", maxTokens: 128, temperature: 0)
                for try await piece in try await engine.stream(request, modelURL: url) { text += piece }
                result["status"] = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "hello" ? "passed" : "instructionMismatch"
            } catch { result["status"] = "failed"; result["error"] = String(describing: error) }
            await engine.unload()
            result["text"] = text
            result["elapsedSeconds"] = Date().timeIntervalSince(started)
            results.append(result)
        }
        let report: [String: Any] = ["results": results, "actualProductionSwiftEngine": true, "iPhoneVerified": false, "promptCountPerModel": 1]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            FileHandle.standardOutput.write(data); print("")
        }
        if results.contains(where: { $0["status"] as? String != "passed" }) { exit(1) }
    }
}
