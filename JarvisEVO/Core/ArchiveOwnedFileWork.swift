import Foundation

/// A successful producer transfers an owned temporary file to its caller. The
/// caller must install cleanup before checking cancellation. Throwing producers
/// remain responsible for any partial output they never returned.
enum ArchiveOwnedFileWork {
    static func run(_ produce: @escaping @Sendable () throws -> URL) async throws -> URL {
        let worker = Task.detached(priority: .utility, operation: produce)
        return try await withTaskCancellationHandler {
            // Do not observe cancellation between successful creation and
            // ownership transfer. The caller installs its defer immediately.
            return try await worker.value
        } onCancel: { worker.cancel() }
    }
}
