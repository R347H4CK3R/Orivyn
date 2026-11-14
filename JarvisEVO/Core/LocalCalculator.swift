import Foundation

/// Bounded, deterministic arithmetic only. Double results are approximate, not
/// exact decimal/financial arithmetic. No eval, script engine, functions or tools.
enum LocalCalculator {
    static let maximumInputBytes = 256
    static let maximumNesting = 32
    static let maximumOperations = 128

    static func evaluate(_ expression: String) throws -> Double {
        guard expression.utf8.count <= maximumInputBytes else { throw LocalCalculatorError.inputTooLong }
        let normalized = expression.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
        let input = Array(normalized.utf8)
        guard input.allSatisfy({ (48...57).contains($0) || [9,10,13,32,40,41,42,43,45,46,47].contains($0) }) else {
            throw LocalCalculatorError.invalidCharacter
        }
        var parser = Parser(input: input)
        parser.skipWhitespace()
        guard parser.index < input.count else { throw LocalCalculatorError.emptyExpression }
        let result = try parser.expression(depth: 0)
        parser.skipWhitespace()
        guard parser.index == input.count else { throw LocalCalculatorError.unexpectedToken }
        return result
    }

    private struct Parser {
        let input: [UInt8]
        var index = 0
        var operations = 0

        mutating func skipWhitespace() {
            while index < input.count && [9,10,13,32].contains(input[index]) { index += 1 }
        }
        mutating func consume(_ byte: UInt8) -> Bool {
            skipWhitespace()
            guard index < input.count && input[index] == byte else { return false }
            index += 1
            return true
        }
        mutating func countOperation() throws {
            guard operations < LocalCalculator.maximumOperations else { throw LocalCalculatorError.operationLimit }
            operations += 1
        }
        func finite(_ value: Double) throws -> Double {
            guard value.isFinite else { throw LocalCalculatorError.nonFiniteResult }
            return value
        }
        mutating func expression(depth: Int) throws -> Double {
            var value = try term(depth: depth)
            while true {
                if consume(43) {
                    try countOperation()
                    value = try finite(value + term(depth: depth))
                } else if consume(45) {
                    try countOperation()
                    value = try finite(value - term(depth: depth))
                } else { return value }
            }
        }
        mutating func term(depth: Int) throws -> Double {
            var value = try factor(depth: depth)
            while true {
                if consume(42) {
                    try countOperation()
                    value = try finite(value * factor(depth: depth))
                } else if consume(47) {
                    try countOperation()
                    let divisor = try factor(depth: depth)
                    guard divisor != 0 else { throw LocalCalculatorError.divisionByZero }
                    value = try finite(value / divisor)
                } else { return value }
            }
        }
        mutating func factor(depth: Int) throws -> Double {
            // Unary chains consume the shared operation budget without recursion.
            var negative = false
            while true {
                if consume(43) { try countOperation() }
                else if consume(45) { try countOperation(); negative.toggle() }
                else { break }
            }
            let value: Double
            if consume(40) {
                guard depth < LocalCalculator.maximumNesting else { throw LocalCalculatorError.nestingLimit }
                value = try expression(depth: depth + 1)
                guard consume(41) else { throw LocalCalculatorError.missingClosingParenthesis }
            } else { value = try number() }
            return try finite(negative ? -value : value)
        }
        mutating func number() throws -> Double {
            skipWhitespace()
            let start = index
            var digits = 0
            while index < input.count && (48...57).contains(input[index]) { index += 1; digits += 1 }
            if index < input.count && input[index] == 46 {
                index += 1
                while index < input.count && (48...57).contains(input[index]) { index += 1; digits += 1 }
            }
            guard digits > 0 else { throw LocalCalculatorError.invalidNumber }
            let text = String(decoding: input[start..<index], as: UTF8.self)
            guard let value = Double(text) else { throw LocalCalculatorError.invalidNumber }
            return try finite(value)
        }
    }
}

enum LocalCalculatorError: LocalizedError, Equatable {
    case inputTooLong, emptyExpression, invalidCharacter, invalidNumber
    case unexpectedToken, missingClosingParenthesis, divisionByZero, nonFiniteResult
    case nestingLimit, operationLimit

    var errorDescription: String? {
        switch self {
        case .inputTooLong: "Shorten the expression to at most 256 UTF-8 bytes."
        case .emptyExpression: "Enter an arithmetic expression, such as (2 + 3) * 4."
        case .invalidCharacter: "Use only digits, decimal points, whitespace, +, -, *, / and parentheses. Functions, exponents and percentages are not supported."
        case .invalidNumber: "Enter a valid number before continuing the expression. Decimals such as 0.5 are supported."
        case .unexpectedToken: "Check the expression for extra numbers, symbols or parentheses. Write multiplication explicitly, such as 2 * (3 + 4)."
        case .missingClosingParenthesis: "Add the missing closing parenthesis."
        case .divisionByZero: "Division by zero is undefined. Change the denominator to a nonzero value."
        case .nonFiniteResult: "The calculation exceeds the finite number range. Use smaller values or a different expression."
        case .nestingLimit: "Use at most 32 nested parentheses."
        case .operationLimit: "Simplify the expression to at most 128 operations, including unary signs."
        }
    }
}
