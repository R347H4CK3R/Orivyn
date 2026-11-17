import Foundation

/// Keeps temporary Foundation read objects scoped to one bounded chunk on Apple
/// platforms. The returned Data retains its bytes normally after the pool drains.
/// Errors and EOF remain FileHandle's; no reads or cancellation are hidden.
enum ArchiveReadBuffer {
    enum Failure: Error { case invalidCount }
    static func read(_ handle: FileHandle, upToCount count: Int) throws -> Data? {
        guard (1...65_536).contains(count) else { throw Failure.invalidCount }
        #if canImport(ObjectiveC)
        return try autoreleasepool { try handle.read(upToCount: count) }
        #else
        return try handle.read(upToCount: count)
        #endif
    }
}
