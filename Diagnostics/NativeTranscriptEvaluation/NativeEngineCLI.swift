import Foundation
import llama

/// Host process for the actual production actor. No model/provider doubles.
@main struct NativeEngineCLI {
    static func main() async {
        do {
            guard CommandLine.arguments.count==3 else { throw LocalAgentError.invalidState }
            CommandLine.arguments[2].withCString { ggml_backend_load_all_from_path($0) }
            let value=try MCPJSONValue.parse(FileHandle.standardInput.readDataToEndOfFile(),maximumBytes:65536)
            guard let fields=value.objectValue,let state=fields["state"]?.stringValue,
                  let scope=fields["scope"]?.objectValue,let query=scope["query"]?.stringValue,
                  case .integer(let index)?=scope["messageIndex"] else { throw LocalAgentError.invalidState }
            let engine=LlamaEngine()
            var request=GenerationRequest.nativeTranscript(stateJSON:state,query:query,messageIndex:index)
            if fields["reviewed"] == .bool(true) {
                guard let approved=try GenerationRequest.reviewedNative(stateJSON:state) else { throw LocalAgentError.invalidState }
                request=approved
            }
            if fields["regularProbe"] == .bool(true) {
                request=GenerationRequest(messages:[ChatMessage(role:.user,content:"Reply with just hello.")],systemPrompt:"Follow the user.",maxTokens:64,temperature:0,conciseQwen3:true)
            }
            if fields["conflictingMode"] == .bool(true) { request.localAgentRequiresTool=true }
            let stream=try await engine.stream(request,modelURL:URL(fileURLWithPath:CommandLine.arguments[1]))
            if fields["cancelProbe"] == .bool(true) {
                let reader=Task { () async throws -> String in
                    var text=""
                    for try await part in stream { text += part }
                    return text
                }
                var sealed=false
                for _ in 0..<1200 {
                    let directories=(try? FileManager.default.contentsOfDirectory(at:FileManager.default.temporaryDirectory,includingPropertiesForKeys:nil)) ?? []
                    sealed=directories.filter{$0.lastPathComponent.hasPrefix("OrivynNativeModel-")}.contains { directory in
                        let values=try? FileManager.default.attributesOfItem(atPath:directory.appendingPathComponent("model.gguf").path)
                        return (values?[.posixPermissions] as? NSNumber)?.intValue == 0o400
                    }
                    if sealed { break }
                    try await Task.sleep(for:.milliseconds(50))
                }
                reader.cancel()
                await engine.unload()
                var partial=""
                do { partial=try await reader.value } catch is CancellationError { }
                guard sealed,partial.isEmpty else { throw LocalAgentError.invalidState }
                FileHandle.standardOutput.write(try MCPJSONValue.object(["decision":.string("cancelled without a partial decision")]).encoded())
                return
            }
            var output=""
            for try await part in stream {
                output += part
            }
            await engine.unload()
            let result:MCPJSONValue = .object(["decision":.string(output)])
            FileHandle.standardOutput.write(try result.encoded(maximumBytes:32768))
        } catch {
            FileHandle.standardError.write(Data("Native engine rejected: \(error)\n".utf8))
            exit(1)
        }
    }
}
