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
    var version: Int = 1
    var completionContract: LocalCompletionContract? = nil
}

// Durable version routing is explicit. Unsupported or mixed scope metadata must
// fail before a saved record can reach the generic inference/dispatch branch.
extension LocalAgentSnapshot {
    private enum CodingKeys: String, CodingKey {
        case readPlan, approvalRevision, history, id, goal, status, revision, steps, pending, answer, error, version, completionContract
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .version)
        let plan = try c.decodeIfPresent(LocalReadPlan.self, forKey: .readPlan)
        let contract = try c.decodeIfPresent(LocalCompletionContract.self, forKey: .completionContract)
        let approval = try c.decodeIfPresent(Int.self, forKey: .approvalRevision)
        switch version {
        case 1:
            guard !c.contains(.readPlan), !c.contains(.completionContract), !c.contains(.approvalRevision) else { throw LocalAgentError.invalidState }
        case 2:
            guard plan != nil, approval == 0, !c.contains(.completionContract) else { throw LocalAgentError.invalidState }
        case 3:
            guard contract != nil, approval == 0, !c.contains(.readPlan) else { throw LocalAgentError.invalidState }
        default: throw LocalAgentError.invalidState
        }
        self.init(readPlan:plan, approvalRevision:approval,
                  history:try c.decode([Event].self, forKey:.history),
                  id:try c.decode(String.self, forKey:.id), goal:try c.decode(String.self, forKey:.goal),
                  status:try c.decode(String.self, forKey:.status), revision:try c.decode(Int.self, forKey:.revision),
                  steps:try c.decode(Int.self, forKey:.steps), pending:try c.decodeIfPresent(Intent.self, forKey:.pending),
                  answer:try c.decodeIfPresent(String.self, forKey:.answer), error:try c.decodeIfPresent(String.self, forKey:.error),
                  version:version, completionContract:contract)
        if let contract {
            try contract.validateRecordedShape(history:history,pending:pending,approvalRevision:approval)
            if status == "answered" {
                guard try LocalCompletionPolicy.derive(contract:contract,history:history).canAnswer else { throw LocalAgentError.invalidState }
            }
        }
    }
}
