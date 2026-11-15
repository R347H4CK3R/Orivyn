import Foundation

/// Diagnostic process boundary, not an application route. Input state must first
/// pass unchanged JS reducer validation. No model load or tools execute here.
@main struct NativeTranscriptCLI {
    static func main() throws {
        let data=FileHandle.standardInput.readDataToEndOfFile()
        let input=try MCPJSONValue.parse(data,maximumBytes:65536)
        guard let fields=input.objectValue,
              let mode=fields["mode"]?.stringValue,
              let rawState=fields["state"]?.stringValue,
              let templateHash=fields["templateSHA256"]?.stringValue,
              let modelHash=fields["modelSHA256"]?.stringValue,
              modelHash==NativeToolTranscript.modelSHA256 else { throw NativeToolTranscript.Failure.invalidInput }
        guard Set(fields.keys).subtracting(["scope"])==(mode=="render" ? Set(["mode","state","templateSHA256","modelSHA256"]) : Set(["mode","state","templateSHA256","modelSHA256","response"])) else { throw NativeToolTranscript.Failure.invalidInput }
        _=try MCPJSONValue.parse(Data(rawState.utf8),maximumBytes:32768)
        let state=try JSONDecoder().decode(LocalAgentSnapshot.self,from:Data(rawState.utf8))
        var scope:NativeToolTranscript.ReadScope?
        if let value=fields["scope"] {
            guard let a=value.objectValue,Set(a.keys)==["query","messageIndex"],
                  let query=a["query"]?.stringValue,case .integer(let index)?=a["messageIndex"] else { throw NativeToolTranscript.Failure.invalidInput }
            scope = .init(query:query,messageIndex:index)
        }
        let transcript=try NativeToolTranscript.build(state,templateSHA256:templateHash,readScope:scope)
        let result:MCPJSONValue
        switch mode {
        case "render":
            result = .object(["prompt":.string(transcript.prompt),"remainingCalls":.integer(Int64(transcript.remainingCalls)),
                              "allowedIDs":.array(transcript.allowedIDs.sorted().map{.string($0)}),"grammar":try transcript.responseGrammar().map{.string($0)} ?? .null])
        case "parse":
            guard let response=fields["response"]?.stringValue else { throw NativeToolTranscript.Failure.invalidInput }
            result = .object(["decision":.string(try NativeToolResponseAdapter.decision(response,transcript:transcript))])
        default: throw NativeToolTranscript.Failure.invalidInput
        }
        FileHandle.standardOutput.write(try result.encoded(maximumBytes:65536))
    }
}
