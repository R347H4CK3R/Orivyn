import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct MCPEndpoint: Hashable, Sendable {
    let url: URL
    private init(url: URL) { self.url = url }
    static func validated(_ text: String) throws -> Self {
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !text.isEmpty, text.utf8.count <= 4_096,
              text.rangeOfCharacter(from: forbidden) == nil,
              let decoded = text.removingPercentEncoding, decoded.rangeOfCharacter(from: forbidden) == nil,
              let url = URL(string: text, encodingInvalidCharacters: false),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65_535).contains($0) }) ?? true else { throw MCPClientFailure(.invalidEndpoint) }
        return Self(url: url)
    }
}

enum MCPFailureCode: Equatable, Sendable {
    case invalidEndpoint, invalidCredential, notInitialized, closed, busy, invalidArguments, unsupportedSchema
    case invalidResponse, responseTooLarge, unsupportedVersion, unsupportedTransport, sessionExpired
    case unknownTool, http(Int), rpc(Int), cancelled, timedOut, network, redirect
}

struct MCPClientFailure: Error, LocalizedError, Equatable, Sendable {
    let code: MCPFailureCode
    let effectMayHaveOccurred: Bool
    init(_ code: MCPFailureCode, effectMayHaveOccurred: Bool = false) {
        self.code = code; self.effectMayHaveOccurred = effectMayHaveOccurred
    }
    var errorDescription: String? {
        let message: String
        switch code {
        case .invalidEndpoint: message = "Enter a valid HTTPS plugin endpoint without credentials, query parameters, fragments or whitespace."
        case .invalidCredential: message = "The token is too long or contains characters that cannot safely be used in an HTTP header."
        case .notInitialized: message = "Connect and discover the plugin again before reviewing a call."
        case .closed: message = "This plugin connection is closed. Connect again to continue."
        case .busy: message = "Another plugin operation is still running."
        case .invalidArguments: message = "Arguments do not match the supported schema or exceed the local limits. Nothing was sent."
        case .unsupportedSchema: message = "This tool uses an invalid or unsupported schema. It cannot be safely validated by this version."
        case .invalidResponse: message = "The plugin returned an invalid, mismatched or unsupported response."
        case .responseTooLarge: message = "The plugin response exceeded the local size or nesting limits."
        case .unsupportedVersion: message = "This plugin does not support MCP 2025-06-18."
        case .unsupportedTransport: message = "This plugin needs a transport or server-request feature this version does not support."
        case .sessionExpired: message = "The plugin session expired. Connect again and review a new call; the old call will not be repeated."
        case .unknownTool: message = "This tool is not in the current validated catalog. Discover and review it again."
        case .http(let status): message = "The plugin returned HTTP \(status). No automatic retry was made."
        case .rpc(let code): message = "The plugin returned JSON-RPC error \(code). No automatic retry was made."
        case .cancelled: message = "The plugin operation was canceled locally."
        case .timedOut: message = "The plugin operation timed out."
        case .network: message = "The plugin connection failed. No automatic retry was made."
        case .redirect: message = "The plugin attempted an HTTP redirect. It was not followed. Use the approved final endpoint instead."
        }
        return message + (effectMayHaveOccurred ? " The server may already have acted. Check its actual state before trying again." : "")
    }
}

indirect enum MCPJSONValue: Codable, Equatable, Sendable {
    case object([String: MCPJSONValue]), array([MCPJSONValue]), string(String), integer(Int64), number(Double), bool(Bool), null
    static let maximumSafeInteger: Int64 = 9_007_199_254_740_991

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode(Int64.self) { self = .integer(value) }
        else if let value = try? c.decode(Double.self), value.isFinite { self = .number(value) }
        else if let value = try? c.decode([String: Self].self) { self = .object(value) }
        else { self = .array(try c.decode([Self].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .integer(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }
    static func parse(_ data: Data, maximumBytes: Int = 1_048_576) throws -> Self {
        guard data.count <= maximumBytes, String(data: data, encoding: .utf8) != nil else { throw MCPClientFailure(.responseTooLarge) }
        var parser = MCPJSONParser(bytes: Array(data))
        let value = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw MCPClientFailure(.invalidResponse) }
        try value.validateBounds()
        return value
    }
    func encoded(maximumBytes: Int = 16_384) throws -> Data {
        try validateBounds()
        var remaining = maximumBytes
        try checkEncodingBudget(&remaining)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= maximumBytes else { throw MCPClientFailure(.responseTooLarge) }
        return data
    }
    private func checkEncodingBudget(_ remaining: inout Int) throws {
        func charge(_ count: Int) throws {
            guard count <= remaining else { throw MCPClientFailure(.responseTooLarge) }
            remaining -= count
        }
        switch self {
        case .object(let values):
            try charge(2 + max(0, values.count - 1))
            for (key, value) in values { try charge(key.utf8.count + 3); try value.checkEncodingBudget(&remaining) }
        case .array(let values):
            try charge(2 + max(0, values.count - 1))
            for value in values { try value.checkEncodingBudget(&remaining) }
        case .string(let value): try charge(value.utf8.count + 2)
        case .integer(let value): try charge(String(value).utf8.count)
        case .number: try charge(1) // Lower bound; the exact encoded byte check follows.
        case .bool(let value): try charge(value ? 4 : 5)
        case .null: try charge(4)
        }
    }
    func validateBounds(depth: Int = 0) throws {
        guard depth <= 32 else { throw MCPClientFailure(.responseTooLarge) }
        switch self {
        case .object(let values):
            guard values.count <= 64 else { throw MCPClientFailure(.responseTooLarge) }
            for (key, value) in values {
                guard key.utf8.count <= 1_024 else { throw MCPClientFailure(.responseTooLarge) }
                try value.validateBounds(depth: depth + 1)
            }
        case .array(let values):
            guard values.count <= 128 else { throw MCPClientFailure(.responseTooLarge) }
            for value in values { try value.validateBounds(depth: depth + 1) }
        case .string(let value):
            guard value.utf8.count <= 1_048_576 else { throw MCPClientFailure(.responseTooLarge) }
        case .integer(let value):
            guard (-Self.maximumSafeInteger...Self.maximumSafeInteger).contains(value) else { throw MCPClientFailure(.invalidArguments) }
        case .number(let value):
            guard value.isFinite,
                  value.rounded() != value || abs(value) <= Double(Self.maximumSafeInteger) else {
                throw MCPClientFailure(.invalidArguments)
            }
        case .bool, .null: break
        }
    }
    var objectValue: [String: Self]? { if case .object(let value) = self { value } else { nil } }
    var arrayValue: [Self]? { if case .array(let value) = self { value } else { nil } }
    var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    var boolValue: Bool? { if case .bool(let value) = self { value } else { nil } }
    var doubleValue: Double? {
        switch self { case .integer(let value): Double(value); case .number(let value): value; default: nil }
    }
    var integerValue: Int64? {
        switch self {
        case .integer(let value): value
        case .number(let value): value.isFinite && value.rounded() == value && abs(value) <= Double(Self.maximumSafeInteger) ? Int64(value) : nil
        default: nil
        }
    }
}

/// Small recursive parser rejects excessive depth and duplicate keys before a
/// general JSON decoder can allocate an unbounded object graph.
private struct MCPJSONParser {
    let bytes: [UInt8]
    var index = 0
    mutating func whitespace() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func value(depth: Int) throws -> MCPJSONValue {
        guard depth <= 32 else { throw MCPClientFailure(.responseTooLarge) }
        whitespace(); guard index < bytes.count else { throw MCPClientFailure(.invalidResponse) }
        switch bytes[index] {
        case 123:
            index += 1; whitespace(); var result: [String: MCPJSONValue] = [:]
            if consume(125) { return .object(result) }
            while true {
                whitespace(); let key = try string()
                guard result[key] == nil, result.count < 64 else { throw MCPClientFailure(.invalidResponse) }
                whitespace(); guard consume(58) else { throw MCPClientFailure(.invalidResponse) }
                result[key] = try value(depth: depth + 1); whitespace()
                if consume(125) { return .object(result) }
                guard consume(44) else { throw MCPClientFailure(.invalidResponse) }
            }
        case 91:
            index += 1; whitespace(); var result: [MCPJSONValue] = []
            if consume(93) { return .array(result) }
            while true {
                guard result.count < 128 else { throw MCPClientFailure(.responseTooLarge) }
                result.append(try value(depth: depth + 1)); whitespace()
                if consume(93) { return .array(result) }
                guard consume(44) else { throw MCPClientFailure(.invalidResponse) }
            }
        case 34: return .string(try string())
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            let raw = Data(bytes[start..<index])
            guard !raw.isEmpty else { throw MCPClientFailure(.invalidResponse) }
            let token = String(decoding: raw, as: UTF8.self)
            guard token.range(of: #"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { throw MCPClientFailure(.invalidResponse) }
            if !token.contains("."), !token.lowercased().contains("e") {
                guard let number = Int64(token), (-MCPJSONValue.maximumSafeInteger...MCPJSONValue.maximumSafeInteger).contains(number) else { throw MCPClientFailure(.invalidResponse) }
                return .integer(number)
            }
            guard let number = Double(token), number.isFinite else { throw MCPClientFailure(.invalidResponse) }
            // A nonzero JSON value must not become zero and bypass sign/range checks.
            // Exponent digits do not make a zero significand nonzero (0e-999 is zero).
            let significand = token.prefix { $0 != "e" && $0 != "E" }
            let nonzero = significand.utf8.contains { (49...57).contains($0) }
            guard number != 0 || !nonzero else { throw MCPClientFailure(.invalidResponse) }
            return .number(number)
        }
    }
    mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }; index += 1; return true
    }
    mutating func literal(_ text: String) throws {
        let expected = Array(text.utf8)
        guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else { throw MCPClientFailure(.invalidResponse) }
        index += expected.count
    }
    mutating func string() throws -> String {
        let start = index; guard consume(34) else { throw MCPClientFailure(.invalidResponse) }
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if escaped { escaped = false; continue }
            if byte == 92 { escaped = true; continue }
            if byte == 34 {
                guard let text = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) else { throw MCPClientFailure(.invalidResponse) }
                return text
            }
            guard byte >= 32 else { throw MCPClientFailure(.invalidResponse) }
        }
        throw MCPClientFailure(.invalidResponse)
    }
}

struct MCPServerInfo: Equatable, Sendable { let name: String; let version: String }
struct MCPToolDefinition: Identifiable, Equatable, Sendable {
    let name: String
    var title: String? = nil
    var description: String? = nil
    let inputSchema: MCPToolSchema
    var outputSchema: MCPToolSchema? = nil
    var annotations: MCPJSONValue? = nil
    var id: String { name }
}
enum MCPContent: Equatable, Sendable { case text(String), image(data: Data, mimeType: String) }
struct MCPToolCallResult: Equatable, Sendable {
    let content: [MCPContent]
    let structuredContent: MCPJSONValue?
    let isError: Bool
}
struct MCPHTTPResponse: Sendable {
    let url: URL
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}
protocol MCPHTTPTransport: Sendable {
    func send(_ request: URLRequest, maximumResponseBytes: Int, timeout: TimeInterval) async throws -> MCPHTTPResponse
}
