import Foundation

/// Normal chat only. Legacy reviewed checklist schemas remain three-read-only.
/// Arithmetic has no new data access and is bound to the original user expression.
enum NormalChatToolAction: Equatable, Sendable {
    case read(LocalCompletionContract.Action)
    case calculate(String)

    static var allowedNames: [String] { DirectChatRead.allCases.map(\.rawValue) + ["calculate"] }
    var name: String { if case .read(let action) = self { return action.name }; return "calculate" }
    var arguments: MCPJSONValue {
        switch self {
        case .read(let action): return action.arguments
        case .calculate(let expression): return .object(["expression": .string(expression)])
        }
    }
    init(value: MCPJSONValue) throws {
        guard let object = value.objectValue, Set(object.keys) == ["name", "arguments"],
              let name = object["name"]?.stringValue, let arguments = object["arguments"] else { throw LocalAgentError.invalidState }
        if name == "calculate" {
            guard let args = arguments.objectValue, Set(args.keys) == ["expression"],
                  let expression = args["expression"]?.stringValue else { throw LocalAgentError.invalidState }
            _ = try LocalCalculator.evaluate(expression)
            self = .calculate(expression)
        } else {
            guard DirectChatRead(rawValue: name) != nil else { throw LocalAgentError.invalidState }
            self = .read(try LocalCompletionContract.Action(value: value))
        }
    }
    func validateGoal(_ goal: String) throws {
        if case .calculate(let expression) = self {
            _ = try LocalCalculatorRequest.validatedExpression(goal: goal, proposed: expression)
        }
    }
    func validateResult(_ result: String, goal: String) throws {
        switch self {
        case .calculate:
            guard LocalCalculationEvidence.validated(goal: goal, arguments: arguments, result: result) != nil else { throw LocalAgentError.invalidState }
        case .read(let action):
            let contract = try LocalCompletionContract(value: .object(["schema": .integer(1), "steps": .array([
                .object(["name": .string(action.name), "arguments": action.arguments])])]))
            _ = try LocalCompletionPolicy.derive(contract: contract, history: [
                .init(operationID: UUID().uuidString, name: action.name, arguments: action.arguments, outcome: "succeeded", result: result)])
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.read(let a), .read(let b)): return a == b
        case (.calculate(let a), .calculate(let b)): return a.utf8.elementsEqual(b.utf8)
        default: return false
        }
    }
}
