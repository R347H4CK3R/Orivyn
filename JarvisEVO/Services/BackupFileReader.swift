import Foundation
import Darwin

/// File-provider work stays off MainActor. Metadata is not an allocation limit:
/// the stream itself is bounded even if an external file changes while selected.
enum BackupFileReader {
    static func read(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var result: Result<Data, any Error>?
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { selectedURL in
                result = Result { try readBounded(selectedURL) }
            }
            try Task.checkCancellation()
            if let coordinationError { throw coordinationError }
            guard let result else { throw BackupFileReadError.unavailable }
            return try result.get()
        }
        return try await withTaskCancellationHandler {
            let data = try await task.value
            try Task.checkCancellation()
            return data
        } onCancel: { task.cancel() }
    }

    static func readBounded(_ url: URL, maximumBytes: Int = ConversationBackup.maximumBytes) throws -> Data {
        try Task.checkCancellation()
        guard url.isFileURL, maximumBytes > 0, maximumBytes <= ConversationBackup.maximumBytes else {
            throw BackupFileReadError.unavailable
        }
        // Verify the opened descriptor, not a raceable pre-open pathname check.
        // Nonblocking open also avoids hanging if another process replaces it with a FIFO.
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw BackupFileReadError.unavailable }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            Darwin.close(descriptor)
            throw BackupFileReadError.unavailable
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var data = Data()
        while true {
            try Task.checkCancellation()
            // One extra byte detects growth/oversize without reading the whole file.
            let limit = min(65_536, maximumBytes - data.count + 1)
            guard let chunk = try handle.read(upToCount: limit), !chunk.isEmpty else { break }
            guard chunk.count <= maximumBytes - data.count else { throw ConversationError.tooLarge }
            data.append(chunk)
        }
        try Task.checkCancellation()
        guard !data.isEmpty else { throw BackupFileReadError.empty }
        return data
    }
}

private enum BackupFileReadError: LocalizedError {
    case unavailable, empty
    var errorDescription: String? {
        switch self {
        case .unavailable: "Choose a readable regular JSON backup file. If its provider is unavailable, download the file in Files and try again."
        case .empty: "The selected backup file is empty. Your existing history has not been changed."
        }
    }
}
