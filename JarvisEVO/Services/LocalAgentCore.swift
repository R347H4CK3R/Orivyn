import Foundation
import JavaScriptCore

/// Executes only the trusted bundled reducer. Model/task strings are function arguments,
/// never executable JavaScript, and this context exposes no network or native objects.
@MainActor
final class LocalAgentCore {
    private let context: JSContext
    private let api: JSValue
    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "LocalAgentCore", withExtension: "js"),
              let bytes = try? Data(contentsOf: url), bytes.count <= 100_000,
              let source = String(data: bytes, encoding: .utf8), let context = JSContext() else { throw LocalAgentError.unavailable }
        context.evaluateScript(source)
        guard context.exception == nil, let api = context.objectForKeyedSubscript("OrivynLocalAgent"), !api.isUndefined else { throw LocalAgentError.unavailable }
        self.context = context; self.api = api
    }
    func call(_ name: String, _ arguments: [String]) throws -> String {
        guard ["conversationIDs", "create", "prompt", "acceptDecision", "recordResult", "cancel", "recover", "resume", "fail"].contains(name),
              arguments.count <= 2, arguments.allSatisfy({ $0.utf8.count <= 131_072 }) else { throw LocalAgentError.invalidState }
        context.exception = nil
        guard let function = api.forProperty(name), !function.isUndefined,
              let value = function.call(withArguments: arguments), context.exception == nil,
              value.isString, let result = value.toString(), result.utf8.count <= 131_072 else { throw LocalAgentError.invalidState }
        return result
    }
    func snapshot(_ raw: String) throws -> LocalAgentSnapshot {
        guard raw.utf8.count <= 131_072, let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(LocalAgentSnapshot.self, from: data) else { throw LocalAgentError.invalidState }
        return value
    }
}
