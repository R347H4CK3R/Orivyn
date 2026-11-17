import Foundation

/// Bounded top-level array reader. Consumers may write ONLY staging records:
/// a later malformed record or cancellation invalidates the entire preparation.
/// No active history may be committed until this method returns successfully.
enum ChatGPTRecordStream {
    enum Failure: LocalizedError {
        case format, limit
        var errorDescription: String? {
            switch self {
            case .format: return "The conversations file is not valid JSON in a supported export format. Export the conversations again and retry."
            case .limit: return "The conversations file exceeds a safe size, count or nesting limit. Try a smaller export."
            }
        }
    }
    struct Limits { var recordBytes = 16_000_000; var totalBytes = 1_000_000_000; var records = 10_000; var nesting = 128 }
    struct Report { let records: Int; let bytes: Int }
    static func read(_ handle: FileHandle, limits: Limits = Limits(), consume: (Data) throws -> Void) throws -> Report {
        guard (2...16_000_000).contains(limits.recordBytes), (2...1_000_000_000).contains(limits.totalBytes),
              (1...10_000).contains(limits.records), (1...128).contains(limits.nesting) else { throw Failure.limit }
        var phase = 0, mayClose = true, quoted = false, escaped = false
        var bytes = 0, records = 0, object = Data(), stack: [UInt8] = []
        while let chunk = try ArchiveReadBuffer.read(handle, upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            bytes += chunk.count
            guard bytes <= limits.totalBytes else { throw Failure.limit }
            for byte in chunk {
                let whitespace = byte == 32 || byte == 9 || byte == 10 || byte == 13
                switch phase {
                case 0:
                    if whitespace { continue }
                    guard byte == 91 else { throw Failure.format }
                    phase = 1
                case 1:
                    if whitespace { continue }
                    if byte == 93 && mayClose { phase = 4; continue }
                    guard byte == 123 else { throw Failure.format }
                    guard records < limits.records else { throw Failure.limit }
                    object = Data([byte]); stack = [125]; quoted = false; escaped = false; phase = 2
                case 2:
                    object.append(byte)
                    guard object.count <= limits.recordBytes else { throw Failure.limit }
                    if quoted {
                        if escaped { escaped = false }
                        else if byte == 92 { escaped = true }
                        else if byte == 34 { quoted = false }
                    } else {
                        if byte == 34 { quoted = true }
                        else if byte == 123 || byte == 91 {
                            guard stack.count < limits.nesting else { throw Failure.limit }
                            stack.append(byte == 123 ? 125 : 93)
                        } else if byte == 125 || byte == 93 {
                            guard stack.last == byte else { throw Failure.format }
                            stack.removeLast()
                        }
                    }
                    if stack.isEmpty {
                        try ChatGPTRecordProjection.validate(object)
                        try Task.checkCancellation()
                        try consume(object)
                        records += 1; object.removeAll(keepingCapacity: false); phase = 3
                    }
                case 3:
                    if whitespace { continue }
                    if byte == 44 { phase = 1; mayClose = false }
                    else if byte == 93 { phase = 4 }
                    else { throw Failure.format }
                default:
                    guard whitespace else { throw Failure.format }
                }
            }
        }
        try Task.checkCancellation()
        guard phase == 4 else { throw Failure.format }
        return Report(records: records, bytes: bytes)
    }
}

/// Allocation-bounded projection, not a general-purpose JSON object graph.
/// Unknown fields are syntax checked and skipped. Selected duplicate keys (even
/// escaped aliases) are ambiguous and fail closed; unknown duplicates are ignored.
/// Originals remain in the separately preserved archive, not in this projection.
enum ChatGPTRecordProjection {
    enum Failure: LocalizedError {
        case format, limit, duplicateKey
        var errorDescription: String? {
            switch self {
            case .format: "This conversation contains invalid JSON and could not be prepared for import."
            case .duplicateKey: "This conversation contains duplicate fields with ambiguous values and could not be prepared safely. Export it again or import extracted text instead."
            case .limit: "This conversation is too complex to process safely. No conversation was activated by this preparation. Try a smaller or conversation-split export, or import extracted text instead."
            }
        }
    }
    struct Limits {
        var retainedNodes = 100_000
        var retainedBytes = 16_000_000
        var opaqueNodes = 20_000
        var opaqueBytes = 2_000_000
    }
    static func project(_ data: Data, limits: Limits = Limits()) throws -> [String: Any] {
        var scanner = try Scanner(data, limits: limits, retain: true)
        guard let result = try scanner.document() as? [String: Any] else { throw Failure.format }
        return result
    }
    static func validate(_ data: Data) throws {
        var scanner = try Scanner(data, limits: Limits(), retain: false)
        _ = try scanner.document()
    }
    private enum Shape {
        case root, rootMetadata, mapping, node, message, author, metadata, content, parts, attachments, scalar, opaque, skip
        func field(_ key: String) -> Shape {
            switch self {
            case .root:
                if key == "mapping" { return .mapping }
                if key == "metadata" { return .rootMetadata }
                return ["id", "title", "current_node", "create_time", "update_time", "is_archived", "is_do_not_remember"].contains(key) ? .scalar : .skip
            case .rootMetadata: return key == "is_do_not_remember" ? .scalar : .skip
            case .mapping: return .node
            case .node: return key == "parent" ? .scalar : key == "message" ? .message : .skip
            case .message:
                if key == "metadata" { return .metadata }
                if key == "author" { return .author }
                if key == "content" { return .content }
                return ["id", "create_time", "status", "channel", "recipient", "is_do_not_remember"].contains(key) ? .scalar : .skip
            case .author: return key == "role" ? .scalar : .skip
            case .metadata:
                if key == "attachments" { return .attachments }
                return ["is_do_not_remember", "is_visually_hidden_from_conversation", "is_user_system_message"].contains(key) ? .scalar : .skip
            case .content: return key == "parts" ? .parts : key == "content_type" ? .scalar : .skip
            case .opaque: return .opaque
            default: return .skip
            }
        }
    }
    private struct Scanner {
        let data: Data
        let bytes: [UInt8]
        let limits: Limits
        let retain: Bool
        var visitedValues = 0
        var index = 0, retainedNodes = 0, retainedBytes = 0, opaqueNodes = 0, opaqueBytes = 0
        init(_ data: Data, limits: Limits, retain: Bool) throws {
            guard data.count <= 16_000_000, limits.retainedNodes > 0, limits.retainedNodes <= 100_000,
                  limits.retainedBytes > 0, limits.retainedBytes <= 16_000_000,
                  limits.opaqueNodes > 0, limits.opaqueNodes <= 20_000,
                  limits.opaqueBytes > 0, limits.opaqueBytes <= 2_000_000 else { throw Failure.limit }
            // Validates raw UTF-8, including skipped fields, without constructing a DOM.
            guard String(data: data, encoding: .utf8) != nil else { throw Failure.format }
            self.data = data; bytes = Array(data); self.limits = limits; self.retain = retain
        }
        mutating func document() throws -> Any? {
            whitespace(); guard peek == 123 else { throw Failure.format }
            let result = try value(.root, depth: 0)
            whitespace(); guard index == bytes.count else { throw Failure.format }
            return result
        }
        var peek: UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func whitespace() { while let b = peek, b == 32 || b == 9 || b == 10 || b == 13 { index += 1 } }
        mutating func expect(_ b: UInt8) throws { guard peek == b else { throw Failure.format }; index += 1 }
        mutating func charge(_ count: Int) throws {
            retainedBytes += count
            guard retainedBytes <= limits.retainedBytes else { throw Failure.limit }
        }
        mutating func value(_ shape: Shape, depth: Int) throws -> Any? {
            guard depth < 128 else { throw Failure.limit }
            visitedValues += 1
            if visitedValues & 1023 == 0 { try Task.checkCancellation() }
            whitespace(); let start = index
            if shape != .skip {
                retainedNodes += 1
                guard retainedNodes <= limits.retainedNodes else { throw Failure.limit }
            }
            if shape == .opaque {
                // Count/validate complete opaque tree before Foundation allocates it.
                let before = index
                try skipOpaque(depth: depth)
                opaqueBytes += index - before
                guard opaqueBytes <= limits.opaqueBytes else { throw Failure.limit }
                if retain { try charge(index - before); return try scalar(before..<index) }
                return nil
            }
            switch peek ?? 0 {
            case 123:
                index += 1; whitespace()
                var output: [String: Any] = [:], selected = Set<String>(), members = 0
                if peek == 125 { index += 1; return retain && shape != .skip ? output : nil }
                while true {
                    whitespace(); let keyRange = try string()
                    var key: String?, child: Shape = .skip
                    if shape != .skip {
                        // Include fully \uXXXX-escaped aliases of every schema key.
                        // Mapping IDs are arbitrary data and separately byte bounded.
                        if shape == .mapping || keyRange.count <= 512 {
                            if shape == .mapping { try charge(keyRange.count) }
                            key = try scalar(keyRange) as? String
                            guard let decoded = key else { throw Failure.format }
                            child = shape.field(decoded)
                            if child != .skip {
                                guard selected.insert(decoded).inserted else { throw Failure.duplicateKey }
                            }
                        }
                    }
                    whitespace(); try expect(58)
                    let childValue = try value(child, depth: depth + 1)
                    if retain, let key, let childValue { output[key] = childValue }
                    members += 1
                    if shape == .mapping, members > 20_000 { throw Failure.limit }
                    whitespace()
                    if peek == 125 { index += 1; break }
                    try expect(44)
                }
                return retain && shape != .skip ? output : nil
            case 91:
                index += 1; whitespace(); var output: [Any] = [], count = 0
                if peek == 93 { index += 1; return retain && shape != .skip ? output : nil }
                while true {
                    whitespace()
                    let child: Shape = shape == .parts ? (peek == 34 ? .scalar : .opaque) : shape == .attachments ? .opaque : .skip
                    let element = try value(child, depth: depth + 1)
                    if retain, let element { output.append(element) }
                    count += 1
                    if shape == .parts && count > 20_000 || shape == .attachments && count > 2048 { throw Failure.limit }
                    whitespace()
                    if peek == 93 { index += 1; break }
                    try expect(44)
                }
                return retain && shape != .skip ? output : nil
            case 34: _ = try string()
            case 116: try literal("true")
            case 102: try literal("false")
            case 110: try literal("null")
            case 45, 48...57: try number()
            default: throw Failure.format
            }
            if shape != .skip && retain { try charge(index - start); return try scalar(start..<index) }
            return nil
        }
        /// Strict recursive validation/counting without allocating object/key graphs.
        mutating func skipOpaque(depth: Int) throws {
            guard depth < 128 else { throw Failure.limit }
            opaqueNodes += 1
            if opaqueNodes & 1023 == 0 { try Task.checkCancellation() }
            guard opaqueNodes <= limits.opaqueNodes else { throw Failure.limit }
            whitespace()
            switch peek ?? 0 {
            case 123:
                index += 1; whitespace(); if peek == 125 { index += 1; return }
                while true {
                    whitespace(); _ = try string(); whitespace(); try expect(58)
                    try skipOpaque(depth: depth + 1); whitespace()
                    if peek == 125 { index += 1; return }; try expect(44)
                }
            case 91:
                index += 1; whitespace(); if peek == 93 { index += 1; return }
                while true {
                    try skipOpaque(depth: depth + 1); whitespace()
                    if peek == 93 { index += 1; return }; try expect(44)
                }
            case 34: _ = try string()
            case 116: try literal("true")
            case 102: try literal("false")
            case 110: try literal("null")
            case 45, 48...57: try number()
            default: throw Failure.format
            }
        }
        func scalar(_ range: Range<Int>) throws -> Any {
            #if canImport(ObjectiveC)
            return try autoreleasepool { try JSONSerialization.jsonObject(with: data.subdata(in: range), options: [.fragmentsAllowed]) }
            #else
            return try JSONSerialization.jsonObject(with: data.subdata(in: range), options: [.fragmentsAllowed])
            #endif
        }
        mutating func literal(_ text: StaticString) throws {
            for b in String(describing: text).utf8 { try expect(b) }
        }
        mutating func hex4() throws -> UInt32 {
            var result: UInt32 = 0
            for _ in 0..<4 {
                guard let b = peek else { throw Failure.format }; index += 1
                let n: UInt32
                switch b { case 48...57: n = UInt32(b - 48); case 65...70: n = UInt32(b - 55); case 97...102: n = UInt32(b - 87); default: throw Failure.format }
                result = result * 16 + n
            }
            return result
        }
        mutating func string() throws -> Range<Int> {
            let start = index; try expect(34)
            while let b = peek {
                index += 1
                if index & 65535 == 0 { try Task.checkCancellation() }
                if b == 34 { return start..<index }
                guard b >= 32 else { throw Failure.format }
                if b == 92 {
                    guard let escape = peek else { throw Failure.format }; index += 1
                    if escape == 117 {
                        let first = try hex4()
                        if (0xD800...0xDBFF).contains(first) {
                            try expect(92); try expect(117)
                            guard (0xDC00...0xDFFF).contains(try hex4()) else { throw Failure.format }
                        } else if (0xDC00...0xDFFF).contains(first) { throw Failure.format }
                    } else if ![34, 92, 47, 98, 102, 110, 114, 116].contains(escape) { throw Failure.format }
                }
            }
            throw Failure.format
        }
        mutating func number() throws {
            let start = index
            if peek == 45 { index += 1 }
            if peek == 48 { index += 1 }
            else {
                guard let b = peek, (49...57).contains(b) else { throw Failure.format }
                repeat { index += 1 } while peek.map { (48...57).contains($0) } == true
            }
            if peek == 46 {
                index += 1; guard peek.map({ (48...57).contains($0) }) == true else { throw Failure.format }
                repeat { index += 1 } while peek.map { (48...57).contains($0) } == true
            }
            if peek == 101 || peek == 69 {
                index += 1; if peek == 43 || peek == 45 { index += 1 }
                guard peek.map({ (48...57).contains($0) }) == true else { throw Failure.format }
                repeat { index += 1 } while peek.map { (48...57).contains($0) } == true
            }
            guard index - start <= 1024 else { throw Failure.limit }
            guard let n = Double(String(decoding: bytes[start..<index], as: UTF8.self)), n.isFinite else { throw Failure.format }
        }
    }
}
