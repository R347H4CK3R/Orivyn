import Foundation

/// Trusted bundled grammar constrains syntax, not the truth of a model's answer.
/// The reducer independently validates tools, argument bounds and durable state.
enum LocalAgentGrammar {
    static func load(requireTool: Bool, bundle: Bundle = .main) throws -> String {
        let header = "root ::= tool | read-result | answer\n"
        guard let url = bundle.url(forResource: "LocalAgentDecision", withExtension: "gbnf"),
              let data = try? Data(contentsOf: url), data.count <= 8_192,
              let source = String(data: data, encoding: .utf8), source.hasPrefix(header) else { throw LocalAgentError.unavailable }
        return requireTool ? "root ::= tool\n" + String(source.dropFirst(header.count)) : source
    }
}
