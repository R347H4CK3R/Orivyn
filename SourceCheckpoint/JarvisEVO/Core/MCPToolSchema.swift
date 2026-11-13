import Foundation

/// Deliberately limited JSON Schema. Unsupported assertions fail closed instead
/// of being ignored. Descriptions are untrusted annotations, not instructions.
struct MCPToolSchema: Equatable, Sendable {
    let json: MCPJSONValue
    init(json: MCPJSONValue) throws {
        do {
            try json.validateBounds()
            guard try json.encoded(maximumBytes: 65_536).count <= 65_536 else { throw MCPClientFailure(.unsupportedSchema) }
            try Self.check(json, depth: 0, root: true)
            self.json = json
        } catch { throw MCPClientFailure(.unsupportedSchema) }
    }

    func validate(_ value: MCPJSONValue) throws {
        do { try value.validateBounds(); try Self.evaluate(value, schema: json, depth: 0) }
        catch { throw MCPClientFailure(.invalidArguments) }
    }

    private static func check(_ schema: MCPJSONValue, depth: Int, root: Bool = false) throws {
        guard depth <= 8, let s = schema.objectValue, let type = s["type"]?.stringValue,
              ["object", "array", "string", "number", "integer", "boolean", "null"].contains(type),
              !root || type == "object" else { throw MCPClientFailure(.unsupportedSchema) }
        var permitted: Set<String> = ["type", "title", "description", "$schema", "enum"]
        switch type {
        case "object": permitted.formUnion(["properties", "required", "additionalProperties"])
        case "array": permitted.formUnion(["items", "minItems", "maxItems"])
        case "string": permitted.formUnion(["minLength", "maxLength"])
        case "number", "integer": permitted.formUnion(["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"])
        default: break
        }
        guard Set(s.keys).isSubset(of: permitted) else { throw MCPClientFailure(.unsupportedSchema) }
        for key in ["title", "description"] where s[key] != nil {
            guard let text = s[key]?.stringValue, text.utf8.count <= 4_096 else { throw MCPClientFailure(.unsupportedSchema) }
        }
        if let dialect = s["$schema"] {
            guard let text = dialect.stringValue,
                  ["https://json-schema.org/draft/2020-12/schema", "http://json-schema.org/draft-07/schema#", "https://json-schema.org/draft-07/schema#"].contains(text) else {
                throw MCPClientFailure(.unsupportedSchema)
            }
        }
        if let raw = s["enum"] {
            guard let values = raw.arrayValue, !values.isEmpty, values.count <= 32 else { throw MCPClientFailure(.unsupportedSchema) }
            for value in values {
                switch value { case .array, .object: throw MCPClientFailure(.unsupportedSchema); default: break }
                guard matches(value, type: type) else { throw MCPClientFailure(.unsupportedSchema) }
            }
        }
        switch type {
        case "object":
            let properties: [String: MCPJSONValue]
            if let raw = s["properties"] {
                guard let object = raw.objectValue, object.count <= 64 else { throw MCPClientFailure(.unsupportedSchema) }
                properties = object
            } else { properties = [:] }
            for (key, child) in properties {
                guard !key.isEmpty, key.utf8.count <= 128 else { throw MCPClientFailure(.unsupportedSchema) }
                try check(child, depth: depth + 1)
            }
            if let raw = s["required"] {
                guard let values = raw.arrayValue, values.count <= 64 else { throw MCPClientFailure(.unsupportedSchema) }
                let names = values.compactMap(\.stringValue)
                guard names.count == values.count, Set(names).count == names.count,
                      names.allSatisfy({ properties[$0] != nil }) else { throw MCPClientFailure(.unsupportedSchema) }
            }
            if let raw = s["additionalProperties"], raw.boolValue == nil { throw MCPClientFailure(.unsupportedSchema) }
        case "array":
            guard let items = s["items"] else { throw MCPClientFailure(.unsupportedSchema) }
            try check(items, depth: depth + 1)
            try checkLimits(s, minimum: "minItems", maximum: "maxItems", ceiling: 128)
        case "string": try checkLimits(s, minimum: "minLength", maximum: "maxLength", ceiling: 16_384)
        case "number", "integer":
            for key in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"] where s[key] != nil {
                guard let value = s[key]?.doubleValue, value.isFinite else { throw MCPClientFailure(.unsupportedSchema) }
            }
            let lows = [s["minimum"]?.doubleValue, s["exclusiveMinimum"]?.doubleValue].compactMap { $0 }
            let highs = [s["maximum"]?.doubleValue, s["exclusiveMaximum"]?.doubleValue].compactMap { $0 }
            if let low = lows.max(), let high = highs.min(), low > high { throw MCPClientFailure(.unsupportedSchema) }
        default: break
        }
    }
    private static func checkLimits(_ s: [String: MCPJSONValue], minimum: String, maximum: String, ceiling: Int64) throws {
        for key in [minimum, maximum] where s[key] != nil {
            guard let value = s[key]?.integerValue, (0...ceiling).contains(value) else { throw MCPClientFailure(.unsupportedSchema) }
        }
        guard (s[minimum]?.integerValue ?? 0) <= (s[maximum]?.integerValue ?? ceiling) else { throw MCPClientFailure(.unsupportedSchema) }
    }
    private static func matches(_ value: MCPJSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("null", .null): true
        case ("number", .number), ("number", .integer): true
        case ("integer", _): value.integerValue != nil
        default: false
        }
    }
    private static func evaluate(_ value: MCPJSONValue, schema: MCPJSONValue, depth: Int) throws {
        guard depth <= 8, let s = schema.objectValue, let type = s["type"]?.stringValue,
              matches(value, type: type) else { throw MCPClientFailure(.invalidArguments) }
        if let values = s["enum"]?.arrayValue {
            let found = values.contains { candidate in
                if let a = candidate.doubleValue, let b = value.doubleValue { return a == b }
                return candidate == value
            }
            guard found else { throw MCPClientFailure(.invalidArguments) }
        }
        switch value {
        case .object(let object):
            let properties = s["properties"]?.objectValue ?? [:]
            for name in s["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] {
                guard object[name] != nil else { throw MCPClientFailure(.invalidArguments) }
            }
            for (key, child) in object {
                if let property = properties[key] { try evaluate(child, schema: property, depth: depth + 1) }
                else if s["additionalProperties"]?.boolValue == false { throw MCPClientFailure(.invalidArguments) }
            }
        case .array(let array):
            guard let items = s["items"], Int64(array.count) >= (s["minItems"]?.integerValue ?? 0),
                  Int64(array.count) <= (s["maxItems"]?.integerValue ?? 128) else { throw MCPClientFailure(.invalidArguments) }
            for child in array { try evaluate(child, schema: items, depth: depth + 1) }
        case .string(let string):
            let length = Int64(string.unicodeScalars.count)
            guard length >= (s["minLength"]?.integerValue ?? 0), length <= (s["maxLength"]?.integerValue ?? 16_384) else {
                throw MCPClientFailure(.invalidArguments)
            }
        case .number, .integer:
            guard let number = value.doubleValue, number.isFinite else { throw MCPClientFailure(.invalidArguments) }
            if let minimum = s["minimum"]?.doubleValue, number < minimum { throw MCPClientFailure(.invalidArguments) }
            if let maximum = s["maximum"]?.doubleValue, number > maximum { throw MCPClientFailure(.invalidArguments) }
            if let minimum = s["exclusiveMinimum"]?.doubleValue, number <= minimum { throw MCPClientFailure(.invalidArguments) }
            if let maximum = s["exclusiveMaximum"]?.doubleValue, number >= maximum { throw MCPClientFailure(.invalidArguments) }
        case .bool, .null: break
        }
    }
}
