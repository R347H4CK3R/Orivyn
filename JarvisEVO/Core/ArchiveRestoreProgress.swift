import Foundation

/// Lossy display progress only. No archive data, durable state or outcome is
/// carried here. One pending value bounds memory when the UI cannot keep up.
final class ArchiveRestoreProgress: Sendable {
    let stream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    init() {
        let pair = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        stream = pair.stream
        continuation = pair.continuation
    }
    func report(_ value: String) { continuation.yield(String(value.prefix(1000))) }
    func finish() { continuation.finish() }
    deinit { continuation.finish() }
}
