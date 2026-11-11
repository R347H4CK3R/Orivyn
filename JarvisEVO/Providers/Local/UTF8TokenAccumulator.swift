import Foundation

/// Token pieces can stop in the middle of a UTF-8 scalar. Do not insert replacement
/// characters between token boundaries; flush invalid trailing bytes only at the end.
struct UTF8TokenAccumulator {
    private var pending: [UInt8] = []
    mutating func append(_ bytes: [UInt8]) -> String? {
        pending.append(contentsOf: bytes)
        guard let value = String(bytes: pending, encoding: .utf8) else { return nil }
        pending.removeAll(keepingCapacity: true)
        return value.isEmpty ? nil : value
    }
    mutating func finish() -> String {
        defer { pending.removeAll(keepingCapacity: true) }
        return String(decoding: pending, as: UTF8.self)
    }
}
