import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Reads only a bounded regular file into owned bytes, never maps a mutable file.
enum VisionImageFile {
    static func read(_ url: URL) throws -> Data {
        try Task.checkCancellation()
        guard url.isFileURL, !url.path.utf8.contains(0) else { throw CocoaError(.fileReadUnsupportedScheme) }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        let maximum = 10 * 1024 * 1024
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size > 0, info.st_size <= maximum else { throw CocoaError(.fileReadTooLarge) }
        var bytes = Data()
        while let chunk = try file.read(upToCount: min(65536, maximum - bytes.count + 1)), !chunk.isEmpty {
            try Task.checkCancellation()
            guard chunk.count <= maximum - bytes.count else { throw CocoaError(.fileReadTooLarge) }
            bytes.append(chunk)
        }
        guard !bytes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        try Task.checkCancellation()
        return bytes
    }
}
