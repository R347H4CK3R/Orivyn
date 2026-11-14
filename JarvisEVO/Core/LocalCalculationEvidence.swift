import Foundation

/// Recomputed approximate arithmetic evidence, independent of generated prose.
/// A caller must separately require a succeeded `calculate` history event. This
/// validates its content, not the model's answer or the provenance of a transcript.
struct LocalCalculationEvidence: Equatable, Sendable {
    let expression: String
    let result: String

    static func validated(goal: String, arguments: MCPJSONValue, result: String) -> Self? {
        guard result.utf8.count <= 4096 else { return nil }
        do {
            // The strict parser rejects duplicate keys and malformed JSON. The
            // adapter validates the exact argument schema, binds the expression
            // to the trusted goal, and recomputes with the bounded real parser.
            let supplied = try MCPJSONValue.parse(Data(result.utf8), maximumBytes: 4096)
            let recomputed = try LocalCalculatorTool.execute(arguments: arguments, requestedGoal: goal)
            let expected = try MCPJSONValue.parse(Data(recomputed.utf8), maximumBytes: 4096)
            guard supplied == expected, let object = expected.objectValue,
                  let expression = object["expression"]?.stringValue,
                  let number = object["result"]?.stringValue else { return nil }
            return Self(expression: expression, result: number)
        } catch { return nil }
    }
}
