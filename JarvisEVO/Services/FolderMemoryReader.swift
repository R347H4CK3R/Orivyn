import Foundation

/// Holds the Files permission for the whole coordinated scan, never the review UI.
enum FolderMemoryReader {
    static func read(_ url: URL, progress: @escaping @Sendable (String) -> Void) async throws -> FolderMemoryImport.Review {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var coordinationError: NSError?
            var result: Result<FolderMemoryImport.Review, any Error>?
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { selected in
                result = Result { try FolderMemoryImport.scan(selected, progress: progress) }
            }
            try Task.checkCancellation()
            if let coordinationError { throw coordinationError }
            guard let result else { throw FolderMemoryImport.Failure.unreadable }
            return try result.get()
        }
        return try await withTaskCancellationHandler {
            let review = try await worker.value
            try Task.checkCancellation()
            return review
        } onCancel: { worker.cancel() }
    }
}
