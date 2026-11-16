import Foundation

/// Holds Files-provider coordination and security-scoped access until preparation
/// actually returns, including cancellation. This bridge never activates history.
enum ArchiveRestoreFileReader {
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "The selected ZIP could not be read. Download it in Files and try again. Existing history is unchanged." }
    }

    static func read<Output: Sendable>(_ url: URL,
        operation: @escaping @Sendable (URL) throws -> Output) async throws -> Output {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard url.isFileURL else { throw Failure.unavailable }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var prepared: Result<Output, any Error>?
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
                prepared = Result {
                    try Task.checkCancellation()
                    return try operation(coordinated)
                }
            }
            try Task.checkCancellation()
            if let coordinationError { throw coordinationError }
            guard let prepared else { throw Failure.unavailable }
            return try prepared.get()
        }
        return try await withTaskCancellationHandler {
            let output = try await worker.value
            try Task.checkCancellation()
            return output
        } onCancel: {
            worker.cancel()
        }
    }
}
