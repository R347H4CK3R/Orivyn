import XCTest
@testable import JarvisEVO

final class MCPUnicodeSchemaTests: XCTestCase {
    private let composed = "\u{e9}"
    private let decomposed = "e\u{301}"

    func testStringEnumRequiresExactCodepointsNotCanonicalEquivalence() throws {
        let schema = try MCPToolSchema(json: .object([
            "type": .string("object"), "properties": .object([
                "value": .object(["type": .string("string"), "enum": .array([.string(composed)])])
            ])
        ]))
        XCTAssertNoThrow(try schema.validate(.object(["value": .string(composed)])))
        XCTAssertThrowsError(try schema.validate(.object(["value": .string(decomposed)])))
    }

    func testRequiredPropertyMustHaveExactKeyBytes() throws {
        let schema = try MCPToolSchema(json: .object([
            "type": .string("object"), "properties": .object([composed: .object(["type": .string("string")])]),
            "required": .array([.string(composed)])
        ]))
        XCTAssertNoThrow(try schema.validate(.object([composed: .string("present")])))
        XCTAssertThrowsError(try schema.validate(.object([decomposed: .string("different key")])))
    }

    func testAdditionalPropertyPolicyDoesNotNormalizeKeys() throws {
        let schema = try MCPToolSchema(json: .object([
            "type": .string("object"), "properties": .object([composed: .object(["type": .string("string")])]),
            "additionalProperties": .bool(false)
        ]))
        XCTAssertThrowsError(try schema.validate(.object([decomposed: .string("different key")])))
        XCTAssertNoThrow(try schema.validate(.object([composed: .string("same key")])))
    }

    func testRequiredSchemaNameMustExactlyMatchDeclaredProperty() {
        XCTAssertThrowsError(try MCPToolSchema(json: .object([
            "type": .string("object"), "properties": .object([composed: .object(["type": .string("string")])]),
            "required": .array([.string(decomposed)])
        ])))
    }

    func testAllowedAdditionalPropertyRetainsOriginalKeyAndValueBytes() throws {
        let schema = try MCPToolSchema(json: .object([
            "type": .string("object"), "properties": .object([composed: .object(["type": .string("integer")])]),
            "additionalProperties": .bool(true)
        ]))
        let value: MCPJSONValue = .object([decomposed: .string(decomposed)])
        XCTAssertNoThrow(try schema.validate(value), "This is an additional key, not the integer property")
        XCTAssertEqual(Array(try value.encoded()), Array("{\"e\u{301}\":\"e\u{301}\"}".utf8))
    }
}
