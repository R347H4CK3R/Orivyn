import Foundation

/// An immutable review-freshness binding, not permissions or an authenticity token.
/// The session owns whether a person explicitly approves and whether review expires.
struct LocalCompletionReview {
    let goal: String
    let contract: LocalCompletionContract
    private let providerID: String
    private let modelSHA256: String
    private let contractData: Data

    init(goal: String, contract: LocalCompletionContract, providerID: String, modelSHA256: String) throws {
        guard Self.validText(goal, maximumBytes: 512), Self.validText(providerID),
              modelSHA256.utf8.count == 64,
              modelSHA256.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw LocalAgentError.invalidState
        }
        self.goal = goal; self.contract = contract
        self.providerID = providerID; self.modelSHA256 = modelSHA256
        // MCPJSONValue encoding sorts object keys but does not normalize string bytes.
        contractData = Data(try contract.encoded().utf8)
    }
    func matches(goal: String, contract: LocalCompletionContract, providerID: String, modelSHA256: String) throws -> Bool {
        let candidate = try Self(goal: goal, contract: contract, providerID: providerID, modelSHA256: modelSHA256)
        return self.goal.utf8.elementsEqual(candidate.goal.utf8) &&
            self.providerID.utf8.elementsEqual(candidate.providerID.utf8) &&
            self.modelSHA256.utf8.elementsEqual(candidate.modelSHA256.utf8) &&
            contractData == candidate.contractData
    }
    private static func validText(_ text: String, maximumBytes: Int? = nil) -> Bool {
        if let maximumBytes, text.utf8.count > maximumBytes { return false }
        // Same nonempty and control-byte rules as the reducer, without trimming.
        return text.unicodeScalars.contains { !isReducerWhitespace($0.value) } &&
            !text.unicodeScalars.contains { $0.value < 32 && ![9,10,13].contains($0.value) }
    }
    private static func isReducerWhitespace(_ value: UInt32) -> Bool {
        (0x09...0x0D).contains(value) || (0x2000...0x200A).contains(value) ||
        [0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF].contains(value)
    }
}
