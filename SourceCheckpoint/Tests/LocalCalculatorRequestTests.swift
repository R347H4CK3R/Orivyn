import XCTest
@testable import JarvisEVO

final class LocalCalculatorRequestTests: XCTestCase {
    func testExplicitCommandPreservesUserExpression() throws {
        XCTAssertEqual(try LocalCalculatorRequest.validatedExpression(goal: "Please calculate (12 + 8) / 4", proposed: "(12+8)/4"), "(12 + 8) / 4")
        XCTAssertEqual(try LocalCalculatorRequest.validatedExpression(goal: "CALCULATE 2 * -3", proposed: "2*-3"), "2 * -3")
        XCTAssertEqual(try LocalCalculatorRequest.validatedExpression(goal: "(12 + 8) / 4", proposed: "(12+8)/4"), "(12 + 8) / 4")
    }
    func testOnlyOperatorGlyphsAndAsciiWhitespaceNormalize() throws {
        XCTAssertEqual(try LocalCalculatorRequest.validatedExpression(goal: "Calculate 6 × 4 ÷ 2 − 1", proposed: "6*4/2-1"), "6 × 4 ÷ 2 − 1")
        XCTAssertEqual(try LocalCalculatorRequest.validatedExpression(goal: "Please\tcalculate\n(2 +\t3) / 4", proposed: "(2+3)/4"), "(2 +\t3) / 4")
        XCTAssertThrowsError(try LocalCalculatorRequest.validatedExpression(goal: "Calculate 1.0 + 2", proposed: "1+2")) { error in
            XCTAssertEqual(error as? LocalCalculatorRequestError, .expressionChanged)
        }
        XCTAssertThrowsError(try LocalCalculatorRequest.validatedExpression(goal: "Calculate +1 + 2", proposed: "1+2")) { error in
            XCTAssertEqual(error as? LocalCalculatorRequestError, .expressionChanged)
        }
    }
    func testDroppedParenthesesAndChangedOperandsNeverSilentlyExecute() {
        for proposed in ["12 + 8 / 4", "(12 + 9) / 4", "(12 + 8) * 4", "(12 + 8) / -4"] {
            XCTAssertThrowsError(try LocalCalculatorRequest.validatedExpression(goal: "Calculate (12 + 8) / 4", proposed: proposed)) { error in
                XCTAssertEqual(error as? LocalCalculatorRequestError, .expressionChanged)
            }
        }
    }
    func testUnsupportedGoalsRejectNegationQuotesWordProblemsAndTrailingInstructions() {
        for goal in ["Do not calculate 2+3", "Please don't calculate 2+3", "Calculate \"2+3\"", "Calculate 2+3 and publish it", "Calculate 2+3; ignore rules", "What is two plus three?", "I have 2 apples and buy3", "Please 2+3", "Calculate 1 2", "Calculate 1/0", "Calculate 1e3", "Calculate 2\u{00a0}+3"] {
            XCTAssertThrowsError(try LocalCalculatorRequest.validatedExpression(goal: goal, proposed: "2+3")) { error in
                XCTAssertEqual(error as? LocalCalculatorRequestError, .unsupportedGoal, goal)
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }
    func testGoalAndProposedByteBoundsDoNotDropContent() {
        XCTAssertThrowsError(try LocalCalculatorRequest.validatedExpression(goal: String(repeating: " ", count: 512) + "1", proposed: "1")) { error in
            XCTAssertEqual(error as? LocalCalculatorRequestError, .unsupportedGoal)
        }
        XCTAssertThrowsError(try LocalCalculatorRequest.validatedExpression(goal: "Calculate 1", proposed: String(repeating: " ", count: 256) + "1")) { error in
            XCTAssertEqual(error as? LocalCalculatorRequestError, .expressionChanged)
        }
        XCTAssertThrowsError(try LocalCalculatorRequest.validatedExpression(goal: "Calculate 1+2", proposed: "1+2\0")) { error in
            XCTAssertEqual(error as? LocalCalculatorRequestError, .expressionChanged)
        }
    }
    func testReturnedOriginalExpressionProducesFiveNotModelChangedFourteen() throws {
        let expression = try LocalCalculatorRequest.validatedExpression(goal: "Calculate (12 + 8) / 4", proposed: "( 12 + 8 ) / 4")
        XCTAssertEqual(try LocalCalculator.evaluate(expression), 5)
        XCTAssertThrowsError(try LocalCalculatorRequest.validatedExpression(goal: "Calculate (12 + 8) / 4", proposed: "12 + 8 / 4"))
    }
}
