import XCTest
@testable import JarvisEVO

final class MCPNumberIntegrityTests: XCTestCase {
    func testNonzeroUnderflowIsRejectedInsteadOfTurningIntoZero() {
        for literal in ["1e-400", "-1e-400", "1E-9999", "-0.00000001e-999", "123e-10000"] {
            XCTAssertThrowsError(try MCPJSONValue.parse(Data("{\"amount\":\(literal)}".utf8)), literal)
        }
    }
    func testTinyNegativeCannotPassNonnegativeIntegerSchema() throws {
        let schema = try MCPToolSchema(json: .object(["type": .string("object"), "properties": .object(["amount": .object(["type": .string("integer"), "minimum": .integer(0)])])]))
        XCTAssertThrowsError(try schema.validate(MCPJSONValue.parse(Data(#"{"amount":-1e-400}"#.utf8))))
    }
    func testActualZeroAndRepresentableTinyFractionsRemainSupported() throws {
        for literal in ["0e-400", "-0.000e-9999", "0E+9999", "0.0", "1e-200", "-1e-200", "0.5"] {
            let parsed = try MCPJSONValue.parse(Data(literal.utf8))
            XCTAssertNotNil(parsed.doubleValue, literal)
        }
    }
    func testExponentAndFractionNotationCannotBypassSafeIntegralBound() {
        for literal in ["9007199254740992.0", "9007199254740993e0", "-9007199254740993e0", "1e20"] {
            XCTAssertThrowsError(try MCPJSONValue.parse(Data(literal.utf8)), literal)
        }
        XCTAssertThrowsError(try MCPJSONValue.number(9_007_199_254_740_992).encoded())
    }
    func testSafeIntegralExponentRoundTripsWithoutChangingValue() throws {
        for literal in ["1e3", "-1e3", "9007199254740991e0", "0.125"] {
            let value = try MCPJSONValue.parse(Data(literal.utf8))
            let decoded = try MCPJSONValue.parse(value.encoded())
            XCTAssertEqual(value.doubleValue, decoded.doubleValue, literal)
        }
    }
}
