import Foundation

/// Emit decodable output immediately, repairing known-invalid input using Swift's
/// standard UTF-8 replacement semantics. Only a possibly valid incomplete trailing
/// scalar survives a token boundary, so persistent buffering is at most three bytes.
struct UTF8TokenAccumulator {
    private var pending: [UInt8] = []
    var pendingByteCount: Int { pending.count }

    mutating func append(_ bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty else { return nil }
        var input = pending
        input.append(contentsOf: bytes)
        let boundary = Self.incompleteSuffixStart(input)
        let output = String(decoding: input[..<boundary], as: UTF8.self)
        pending = Array(input[boundary...])
        return output.isEmpty ? nil : output
    }

    mutating func finish() -> String {
        defer { pending.removeAll(keepingCapacity: true) }
        return String(decoding: pending, as: UTF8.self)
    }

    /// The last non-continuation byte can begin an incomplete scalar only if
    /// its lead and any second byte already satisfy the UTF-8 scalar constraints.
    /// Earlier invalid bytes are not retained; String(decoding:) repairs them.
    private static func incompleteSuffixStart(_ bytes: [UInt8]) -> Int {
        let end = bytes.count
        guard end > 0 else { return end }
        for index in stride(from: end - 1, through: max(0, end - 4), by: -1) {
            let lead = bytes[index]
            if (0x80...0xbf).contains(lead) { continue }
            let expected: Int
            switch lead {
            case 0xc2...0xdf: expected = 2
            case 0xe0...0xef: expected = 3
            case 0xf0...0xf4: expected = 4
            default: return end
            }
            let available = end - index
            guard available < expected else { return end }
            if available >= 2 {
                let second = bytes[index + 1]
                // Continuations were checked while scanning backwards. These
                // limits exclude overlong encodings, surrogates and >U+10FFFF.
                if lead == 0xe0 && second < 0xa0 { return end }
                if lead == 0xed && second > 0x9f { return end }
                if lead == 0xf0 && second < 0x90 { return end }
                if lead == 0xf4 && second > 0x8f { return end }
            }
            return index
        }
        return end
    }
}
