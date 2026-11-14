import XCTest
@testable import JarvisEVO

final class LocalCalculatorTests: XCTestCase {
    func testPrecedenceParenthesesAndDecimals() throws {
        XCTAssertEqual(try LocalCalculator.evaluate("2 + 3 * 4"), 14)
        XCTAssertEqual(try LocalCalculator.evaluate("(2 + 3) * 4"), 20)
        XCTAssertEqual(try LocalCalculator.evaluate(".5 + 1.25 - 2."), -0.25)
        XCTAssertEqual(try LocalCalculator.evaluate("18 / 3 / 2"), 3)
    }
    func testUnarySignsAndUnicodeOperators() throws {
        XCTAssertEqual(try LocalCalculator.evaluate("-(3 + 2) * -2"), 10)
        XCTAssertEqual(try LocalCalculator.evaluate("+2 + --3"), 5)
        XCTAssertEqual(try LocalCalculator.evaluate("6 × 4 ÷ 2 − 1"), 11)
        XCTAssertEqual(try LocalCalculator.evaluate("1 - -2"), 3)
    }
    func testWhitespaceAndApproximateDouble() throws {
        XCTAssertEqual(try LocalCalculator.evaluate(" \n 3\t + 4 \r "), 7)
        XCTAssertEqual(try LocalCalculator.evaluate("0.1 + 0.2"), 0.3, accuracy: 1e-15)
    }
    func testNoSilentLetterStrippingUnsupportedSyntaxOrImplicitMultiplication() {
        for input in ["2 apples + 3", "sqrt(4)", "1e3", "NaN", "inf", "2%", "2(3)", "(2)3", "1 2", "1..2", "1,000", "2^3", "2;3", "1\0+2"] {
            XCTAssertThrowsError(try LocalCalculator.evaluate(input), input)
        }
    }
    func testEmptyAndMalformedExpressionsHaveActionableErrors() {
        for input in ["", " ", "()", "1+", "*2", "(1+2", "1+2)", "."] {
            XCTAssertThrowsError(try LocalCalculator.evaluate(input)) { error in
                XCTAssertFalse(error.localizedDescription.isEmpty)
                XCTAssertTrue(error is LocalCalculatorError)
            }
        }
    }
    func testDivideByZeroAndNonFiniteResultReject() {
        for input in ["1/0", "2/(3-3)", "1/-0.0"] {
            XCTAssertThrowsError(try LocalCalculator.evaluate(input)) { error in
                XCTAssertEqual(error as? LocalCalculatorError, .divisionByZero)
            }
        }
        // Binary floating-point cancellation leaves a tiny nonzero denominator;
        // repeated division overflows while staying within256bytes/128operations.
        let overflow = "1" + String(repeating: "/(.3-.2-.1)", count: 19)
        XCTAssertLessThanOrEqual(overflow.utf8.count, 256)
        XCTAssertThrowsError(try LocalCalculator.evaluate(overflow)) { error in
            XCTAssertEqual(error as? LocalCalculatorError, .nonFiniteResult)
        }
    }
    func testInputNestingAndWorkBounds() throws {
        XCTAssertThrowsError(try LocalCalculator.evaluate(String(repeating: " ", count: 256) + "1")) { error in
            XCTAssertEqual(error as? LocalCalculatorError, .inputTooLong)
        }
        XCTAssertEqual(try LocalCalculator.evaluate(String(repeating: "(", count: 32) + "1" + String(repeating: ")", count: 32)), 1)
        XCTAssertThrowsError(try LocalCalculator.evaluate(String(repeating: "(", count: 33) + "1" + String(repeating: ")", count: 33))) { error in
            XCTAssertEqual(error as? LocalCalculatorError, .nestingLimit)
        }
        XCTAssertEqual(try LocalCalculator.evaluate(String(repeating: "-", count: 128) + "1"), 1)
        XCTAssertThrowsError(try LocalCalculator.evaluate(String(repeating: "-", count: 129) + "1")) { error in
            XCTAssertEqual(error as? LocalCalculatorError, .operationLimit)
        }
    }
    func testFiniteLargeAndNegativeValuesAreNotRejected() throws {
        XCTAssertEqual(try LocalCalculator.evaluate("-1000000.25/2"), -500000.125)
        XCTAssertTrue(try LocalCalculator.evaluate(String(repeating: "9", count: 200)).isFinite)
        XCTAssertEqual(try LocalCalculator.evaluate("0/3"), 0)
    }
}
