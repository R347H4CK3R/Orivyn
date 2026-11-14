import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Copies a selected regular file into a new app-owned attachment path.
/// The byte limit is enforced while reading, not only through raceable metadata.
/// The destination's parent must be the app-owned attachment directory.
enum AttachmentFileCopy {
    static func copy(from source: URL, to destination: URL, maximumBytes: Int) throws -> Int {
        try Task.checkCancellation()
        guard source.isFileURL, destination.isFileURL, maximumBytes > 0 else {
            throw AttachmentFileCopyError.unreadable
        }
        let sourceFD = source.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard sourceFD >= 0 else { throw AttachmentFileCopyError.unreadable }
        let input = FileHandle(fileDescriptor: sourceFD, closeOnDealloc: true)
        defer { try? input.close() }
        var attributes = stat()
        guard fstat(sourceFD, &attributes) == 0,
              attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw AttachmentFileCopyError.unreadable
        }

        let destinationFD = destination.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        }
        // Never delete or replace a file that this invocation did not create.
        guard destinationFD >= 0 else { throw AttachmentFileCopyError.destinationUnavailable }
        let output = FileHandle(fileDescriptor: destinationFD, closeOnDealloc: true)
        var committed = false
        defer {
            try? output.close()
            if !committed { try? FileManager.default.removeItem(at: destination) }
        }
        var total = 0
        while true {
            try Task.checkCancellation()
            // At the limit, probe one byte without writing it. Avoid overflow for Int.max.
            let remaining = maximumBytes - total
            let readLimit = remaining >= 65_536 ? 65_536 : remaining + 1
            guard let chunk = try input.read(upToCount: readLimit), !chunk.isEmpty else { break }
            guard chunk.count <= remaining else { throw AttachmentFileCopyError.invalidSize }
            try output.write(contentsOf: chunk)
            total += chunk.count
        }
        guard total > 0 else { throw AttachmentFileCopyError.invalidSize }
        try Task.checkCancellation()
        try output.synchronize()
        try output.close()
        try Task.checkCancellation()
        committed = true
        return total
    }
}

enum AttachmentFileCopyError: LocalizedError {
    case unreadable, invalidSize, destinationUnavailable
    var errorDescription: String? {
        switch self {
        case .unreadable: "Choose a readable regular attachment file. Download it in Files if its provider is unavailable."
        case .invalidSize: "Choose a nonempty file up to 10 MB. The selected file may have changed while it was being imported."
        case .destinationUnavailable: "The attachment could not be saved. Check available storage and try again."
        }
    }
}
