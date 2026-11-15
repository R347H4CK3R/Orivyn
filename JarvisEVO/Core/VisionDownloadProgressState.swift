import Foundation

/// Main-actor UI state uses this identity to reject delayed download callbacks.
/// An old completion must not clear a newer operation's progress either.
struct VisionDownloadProgressState {
    private var activeOperation: UUID?
    private(set) var value: Double?

    mutating func begin() -> UUID {
        let operation = UUID()
        activeOperation = operation
        value = 0
        return operation
    }

    mutating func update(_ value: Double, for operation: UUID) {
        guard activeOperation == operation else { return }
        self.value = value
    }

    mutating func finish(_ operation: UUID) {
        guard activeOperation == operation else { return }
        cancel()
    }

    mutating func cancel() {
        activeOperation = nil
        value = nil
    }
}
