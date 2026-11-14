import Foundation

/// Integrity gate for a model-proposed calculator call. Only explicit arithmetic
/// is supported, not word problems. The model cannot change the user's operands,
/// parentheses, signs or number spelling. No mismatch is automatically repaired.
enum LocalCalculatorRequest {
    static func validatedExpression(goal: String, proposed: String) throws -> String {
        guard goal.utf8.count <= 512 else { throw LocalCalculatorRequestError.unsupportedGoal }
        let expression: String
        if let prefix = goal.range(of: #"(?i)^[ \t\r\n]*(?:please[ \t\r\n]+)?calculate[ \t\r\n]+"#, options: .regularExpression) {
            expression = String(goal[prefix.upperBound...])
        } else {
            expression = goal
        }
        // Validate the full user expression first. No prose, quotes, negation or
        // trailing instructions are discarded to manufacture an arithmetic goal.
        do { _ = try LocalCalculator.evaluate(expression) }
        catch { throw LocalCalculatorRequestError.unsupportedGoal }
        guard proposed.utf8.count <= 256 else { throw LocalCalculatorRequestError.expressionChanged }
        do { _ = try LocalCalculator.evaluate(proposed) }
        catch { throw LocalCalculatorRequestError.expressionChanged }
        guard normalized(expression) == normalized(proposed) else {
            throw LocalCalculatorRequestError.expressionChanged
        }
        return expression
    }

    private static func normalized(_ expression: String) -> String {
        let operators = expression.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
        return String(String.UnicodeScalarView(operators.unicodeScalars.filter { ![9,10,13,32].contains($0.value) }))
    }
}

enum LocalCalculatorRequestError: LocalizedError, Equatable {
    case unsupportedGoal, expressionChanged

    var errorDescription: String? {
        switch self {
        case .unsupportedGoal:
            "Enter one explicit arithmetic expression, optionally starting with Calculate, such as Calculate (12 + 8) / 4. Word problems, quotes and extra instructions are not supported."
        case .expressionChanged:
            "The proposed calculation does not match your expression exactly. No calculation was accepted. Review the original numbers, signs and parentheses. Use Calculator directly if the model keeps changing them."
        }
    }
}
