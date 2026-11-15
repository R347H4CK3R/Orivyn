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
            if fields["regularProbe"] == .bool(true) {
                request=GenerationRequest(messages:[ChatMessage(role:.user,content:"Reply with just hello.")],systemPrompt:"Follow the user.",maxTokens:64,temperature:0,conciseQwen3:true)
            }
            if fields["conflictingMode"] == .bool(true) { request.localAgentRequiresTool=true }
            var output=""
            for try await part in try await engine.stream(request,modelURL:URL(fileURLWithPath:CommandLine.arguments[1])) {
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
