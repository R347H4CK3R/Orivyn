import Foundation

struct LocalAgentSnapshot: Decodable, Identifiable {
    struct Intent: Decodable {
        let operationID: String
        let name: String
        let arguments: MCPJSONValue
    }
    struct Event: Decodable, Identifiable {
        let operationID: String
        let name: String
        let arguments: MCPJSONValue
        let outcome: String
        let result: String?
        var id: String { operationID }
        func calculationEvidence(goal: String) -> LocalCalculationEvidence? {
            guard name == "calculate", outcome == "succeeded", let result else { return nil }
            return LocalCalculationEvidence.validated(goal: goal, arguments: arguments, result: result)
        }
    }
    let readPlan: LocalReadPlan?
    let approvalRevision: Int?
    let history: [Event]
    let id: String
    let goal: String
    let status: String
    let revision: Int
    let steps: Int
    let pending: Intent?
    let answer: String?
    let error: String?
}
