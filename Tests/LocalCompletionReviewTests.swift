import XCTest
@testable import JarvisEVO

final class LocalCompletionReviewTests: XCTestCase {
    private let sha = String(repeating: "a", count: 64)
    private let provider = "local:qwen"
    private let goal = "Check app and memory"
    private func contract(query: String = "Cedar", limit: Int64 = 2, reverse: Bool = false) throws -> LocalCompletionContract {
        let info: MCPJSONValue = .object(["name": .string("get_app_info"), "arguments": .object([:])])
        let memory: MCPJSONValue = .object(["name": .string("search_memory"), "arguments": .object(["query": .string(query), "limit": .integer(limit)])])
        return try LocalCompletionContract(value: .object(["schema": .integer(1), "steps": .array(reverse ? [memory, info] : [info, memory])]))
    }
    func testUnchangedReviewMatchesAndExposesOnlyRequestedScope() throws {
        let contract = try contract()
        let review = try LocalCompletionReview(goal: goal, contract: contract, providerID: provider, modelSHA256: sha)
        XCTAssertEqual(review.goal, goal)
        XCTAssertEqual(review.contract, contract)
        XCTAssertTrue(try review.matches(goal: goal, contract: contract, providerID: provider, modelSHA256: sha))
        XCTAssertTrue(try review.matches(goal: goal, contract: LocalCompletionContract.parse(contract.encoded()), providerID: provider, modelSHA256: sha))
    }
    func testEveryScopeEditInvalidatesReview() throws {
        let original = try contract()
        let review = try LocalCompletionReview(goal: goal, contract: original, providerID: provider, modelSHA256: sha)
        for changed in [try contract(query: "Other"), try contract(limit: 1), try contract(reverse: true)] {
            XCTAssertFalse(try review.matches(goal: goal, contract: changed, providerID: provider, modelSHA256: sha))
        }
        XCTAssertFalse(try review.matches(goal: goal + " ", contract: original, providerID: provider, modelSHA256: sha))
        XCTAssertFalse(try review.matches(goal: goal, contract: original, providerID: provider + "-changed", modelSHA256: sha))
        XCTAssertFalse(try review.matches(goal: goal, contract: original, providerID: provider, modelSHA256: String(repeating: "b", count: 64)))
        XCTAssertFalse(try review.matches(goal: goal, contract: original, providerID: provider, modelSHA256: sha.uppercased()))
    }
    func testCanonicallyEquivalentUnicodeNeverRefreshesConsent() throws {
        let decomposed = "e\u{301}", composed = "é"
        let original = try contract(query: decomposed)
        let review = try LocalCompletionReview(goal: decomposed, contract: original, providerID: decomposed, modelSHA256: sha)
        XCTAssertFalse(try review.matches(goal: composed, contract: original, providerID: decomposed, modelSHA256: sha))
        XCTAssertFalse(try review.matches(goal: decomposed, contract: contract(query: composed), providerID: decomposed, modelSHA256: sha))
        XCTAssertFalse(try review.matches(goal: decomposed, contract: original, providerID: composed, modelSHA256: sha))
        XCTAssertTrue(try review.matches(goal: decomposed, contract: original, providerID: decomposed, modelSHA256: sha))
    }
    func testGoalBoundsAndControlsMatchReducerWithoutTrimmingStoredGoal() throws {
        let contract = try contract()
        for goal in ["", " \t\r\n", "\u{FEFF}", String(repeating: "x", count: 513), String(repeating: "é", count: 257), "x\u{0}", "x\u{B}"] {
            XCTAssertThrowsError(try LocalCompletionReview(goal: goal, contract: contract, providerID: provider, modelSHA256: sha))
        }
        for goal in [String(repeating: "é", count: 256), "\u{85}", "  original\n"] {
            let review = try LocalCompletionReview(goal: goal, contract: contract, providerID: provider, modelSHA256: sha)
            XCTAssertTrue(review.goal.utf8.elementsEqual(goal.utf8))
        }
    }
    func testIdentityAndHashValidationRejectMalformedBindings() throws {
        let contract = try contract()
        for provider in ["", " \t\n", "\u{FEFF}", "x\u{0}"] {
            XCTAssertThrowsError(try LocalCompletionReview(goal: goal, contract: contract, providerID: provider, modelSHA256: sha))
        }
        for sha in ["", String(repeating: "a", count: 63), String(repeating: "a", count: 65), String(repeating: "g", count: 64), String(repeating: "é", count: 64)] {
            XCTAssertThrowsError(try LocalCompletionReview(goal: goal, contract: contract, providerID: provider, modelSHA256: sha))
        }
        let review = try LocalCompletionReview(goal: goal, contract: contract, providerID: provider, modelSHA256: sha)
        XCTAssertThrowsError(try review.matches(goal: goal, contract: contract, providerID: "", modelSHA256: sha))
        XCTAssertThrowsError(try review.matches(goal: goal, contract: contract, providerID: provider, modelSHA256: "invalid"))
    }
}
