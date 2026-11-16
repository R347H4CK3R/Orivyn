import Foundation

/// Bounded top-level array reader. Consumers may write ONLY staging records:
/// a later malformed record or cancellation invalidates the entire preparation.
/// No active history may be committed until this method returns successfully.
enum ChatGPTRecordStream {
    enum Failure: Error { case format, limit }
    struct Limits { var recordBytes = 16_000_000; var totalBytes = 1_000_000_000; var records = 10_000; var nesting = 128 }
    struct Report { let records: Int; let bytes: Int }
    static func read(_ handle: FileHandle, limits: Limits = Limits(), consume: (Data) throws -> Void) throws -> Report {
        guard (2...16_000_000).contains(limits.recordBytes), (2...1_000_000_000).contains(limits.totalBytes),
              (1...10_000).contains(limits.records), (1...128).contains(limits.nesting) else { throw Failure.limit }
        var phase = 0, mayClose = true, quoted = false, escaped = false
        var bytes = 0, records = 0, object = Data(), stack: [UInt8] = []
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
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
                        guard (try JSONSerialization.jsonObject(with: object)) is [String: Any] else { throw Failure.format }
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
