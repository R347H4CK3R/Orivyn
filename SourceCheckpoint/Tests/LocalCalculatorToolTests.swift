import XCTest
@testable import JarvisEVO

final class LocalCalculatorToolTests: XCTestCase {
    func testModelCannotDropParenthesesFromTrustedGoal() throws {
        XCTAssertThrowsError(try LocalCalculatorTool.execute(arguments: .object(["expression": .string("12 + 8 / 4")]), requestedGoal: "Calculate (12 + 8) / 4")) {
            XCTAssertEqual($0 as? LocalCalculatorRequestError, .expressionChanged)
        }
        let result = try LocalCalculatorTool.execute(arguments: .object(["expression": .string("(12+8)/4")]), requestedGoal: "Calculate (12 + 8) / 4")
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])?["result"] as? String, "5")
    }

    func testActualCalculationHasExplicitApproximateResult() throws {
        let text = try LocalCalculatorTool.execute(arguments: .object(["expression": .string("(12 + 8) / 4")]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(object["expression"] as? String, "(12 + 8) / 4")
        XCTAssertEqual(object["result"] as? String, "5")
        XCTAssertEqual(object["approximate"] as? Bool, true)
        XCTAssertEqual(object["engine"] as? String, "local-arithmetic")
    }
    func testMissingAndExtraArgumentsNeverDispatch() {
        for arguments: MCPJSONValue in [.object([:]), .object(["expression": .string("2+2"), "execute": .bool(true)]), .array([]), .object(["expression": .integer(4)]), .object(["expression": .string("")])] {
            XCTAssertThrowsError(try LocalCalculatorTool.execute(arguments: arguments))
        }
    }
    func testParserErrorsAreNotReplacedByFabricatedResults() {
        XCTAssertThrowsError(try LocalCalculatorTool.execute(arguments: .object(["expression": .string("1/0")]))) {
            XCTAssertEqual($0 as? LocalCalculatorError, .divisionByZero)
        }
    }
    func testWholeOutputMustFitBudget() throws {
        let args = MCPJSONValue.object(["expression": .string("2 + 2")])
        XCTAssertThrowsError(try LocalCalculatorTool.execute(arguments: args, maximumBytes: 20))
        let text = try LocalCalculatorTool.execute(arguments: args, maximumBytes: 4096)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])?["result"] as? String, "4")
    }
}
