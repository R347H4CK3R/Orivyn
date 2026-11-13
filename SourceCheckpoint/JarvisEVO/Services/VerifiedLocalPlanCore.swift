import Foundation
import JavaScriptCore

struct VerifiedLocalPlanSnapshot: Decodable, Identifiable {
    let id: String
    let status: String
    let revision: Int
    let attempts: Int
    let completed: Int
    let pending: LocalAgentSnapshot.Intent?
    let evidence: [MCPJSONValue]
    let error: String?
}

/// Only the bundled deterministic planner is evaluated. No model or network context.
@MainActor
final class VerifiedLocalPlanCore {
    private let context: JSContext
    private let api: JSValue
    private let router: JSValue
    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "VerifiedLocalPlan", withExtension: "js"),
              let bytes = try? Data(contentsOf: url), bytes.count <= 100_000,
              let source = String(data: bytes, encoding: .utf8), let context = JSContext() else { throw LocalAgentError.unavailable }
        context.evaluateScript(source)
        guard context.exception == nil, let api = context.objectForKeyedSubscript("OrivynVerifiedLocalPlan"), !api.isUndefined else { throw LocalAgentError.unavailable }
        guard let routerURL = bundle.url(forResource: "LocalReadRequestRouter", withExtension: "js"),
              let routerBytes = try? Data(contentsOf: routerURL), routerBytes.count <= 100_000,
              let routerSource = String(data: routerBytes, encoding: .utf8) else { throw LocalAgentError.unavailable }
        context.evaluateScript(routerSource)
        guard context.exception == nil, let router = context.objectForKeyedSubscript("OrivynLocalReadRouter"), !router.isUndefined else { throw LocalAgentError.unavailable }
        self.context = context; self.api = api; self.router = router
    }
    struct Route: Decodable {
        struct Request: Decodable { let appInfo: Bool; let installedModels: Bool; let searchQuery: String? }
        let status: String
        let message: String
        let request: Request?
    }
    func route(_ text: String) throws -> Route {
        guard text.utf8.count <= 1024 else { throw LocalAgentError.invalidState }
        context.exception = nil
        guard let function = router.forProperty("route"), !function.isUndefined,
              let value = function.call(withArguments: [text]), context.exception == nil,
              value.isString, let result = value.toString(), result.utf8.count <= 8192 else { throw LocalAgentError.invalidState }
        return try JSONDecoder().decode(Route.self, from: Data(result.utf8))
    }
    func call(_ name: String, _ arguments: [String]) throws -> String {
        guard ["create", "next", "record", "recover", "resume", "cancel", "fail", "report"].contains(name),
              arguments.count <= 2, arguments.allSatisfy({ $0.utf8.count <= 131_072 }) else { throw LocalAgentError.invalidState }
        context.exception = nil
        guard let function = api.forProperty(name), !function.isUndefined,
              let result = function.call(withArguments: arguments), context.exception == nil,
              result.isString, let text = result.toString(), text.utf8.count <= 131_072 else { throw LocalAgentError.invalidState }
        return text
    }
    func snapshot(_ text: String) throws -> VerifiedLocalPlanSnapshot {
        try JSONDecoder().decode(VerifiedLocalPlanSnapshot.self, from: Data(text.utf8))
    }
}
