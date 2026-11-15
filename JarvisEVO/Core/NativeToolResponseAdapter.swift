import Foundation

/// Converts syntax only. The returned decision MUST still pass the existing
/// LocalAgentCore.acceptDecision against the current task before any dispatch.
/// This type has no tools, provider, persistence, permission or execution access.
enum NativeToolResponseAdapter {
    static func decision(_ raw:String,transcript:NativeToolTranscript) throws -> String {
        guard raw.utf8.count<=32768 else { throw NativeToolTranscript.Failure.bound }
        let text=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        let open="<tool_call>",close="</tool_call>"
        let value:MCPJSONValue
        if text.contains(open) || text.contains(close) {
            guard transcript.remainingCalls>0,text.hasPrefix(open),text.hasSuffix(close) else { throw NativeToolTranscript.Failure.invalidInput }
            let body=String(text.dropFirst(open.count).dropLast(close.count))
            // Exact one envelope: tags inside arguments are unsupported too.
            guard !body.contains(open),!body.contains(close) else { throw NativeToolTranscript.Failure.invalidInput }
            let call=try MCPJSONValue.parse(Data(body.utf8),maximumBytes:4096)
            guard let fields=call.objectValue,Set(fields.keys)==["name","arguments"],
                  let name=fields["name"]?.stringValue,let arguments=fields["arguments"] else { throw NativeToolTranscript.Failure.invalidInput }
            try transcript.validateNext(name,arguments)
            value = .object(["type":.string("tool"),"name":.string(name),"arguments":arguments])
        } else {
            guard transcript.canAnswer else { throw NativeToolTranscript.Failure.invalidInput }
            try NativeToolTranscript.checkText(text,maximum:4096,allowEmpty:false)
            value = .object(["type":.string("answer"),"text":.string(text)])
        }
        return String(decoding:try value.encoded(maximumBytes:8192),as:UTF8.self)
    }
}
