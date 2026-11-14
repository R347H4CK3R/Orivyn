import Foundation

/// Shared model-tool adapter. The same bounded parser powers the user calculator.
/// Results are data, not executable code, and are never silently truncated.
enum LocalCalculatorTool {
    static func execute(arguments: MCPJSONValue, requestedGoal: String? = nil, maximumBytes: Int = 4096) throws -> String {
        guard let object = arguments.objectValue, Set(object.keys) == Set(["expression"]),
              let expression = object["expression"]?.stringValue,
              !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalAgentError.invalidState
        }
        let verifiedExpression = try requestedGoal.map {
            try LocalCalculatorRequest.validatedExpression(goal: $0, proposed: expression)
        } ?? expression
        let value = try LocalCalculator.evaluate(verifiedExpression)
        let number = String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0 : value)
        let result = MCPJSONValue.object(["expression": .string(verifiedExpression), "result": .string(number),
                                          "approximate": .bool(true), "engine": .string("local-arithmetic")])
        let data = try result.encoded(maximumBytes: maximumBytes)
        guard let text = String(data: data, encoding: .utf8) else { throw LocalAgentError.invalidState }
        return text
    }
}
