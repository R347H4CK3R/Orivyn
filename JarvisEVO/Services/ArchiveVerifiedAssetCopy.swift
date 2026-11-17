import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Copies exact retained evidence through no-follow descriptors. The coordinator
/// serializes app-private roots; only a newly created destination may be removed.
enum ArchiveVerifiedAssetCopy {
    static func copy(root: URL, source: ArchiveAttachmentSupplement.Source, to destination: URL) throws {
        try ArchiveAttachmentSupplement.validate(source)
        try Task.checkCancellation()
        guard root.isFileURL, destination.isFileURL,
              root.standardizedFileURL.path == root.resolvingSymlinksInPath().path,
              destination.deletingLastPathComponent().standardizedFileURL.path == destination.deletingLastPathComponent().resolvingSymlinksInPath().path else {
            throw ArchiveAttachmentSupplement.Failure.invalid
        }
        let parts = source.relativePath.split(separator: "/").map(String.init)
        var directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw ArchiveAttachmentSupplement.Failure.invalid }
        defer { close(directory) }
        for part in parts.dropLast() {
            let next = openat(directory, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw ArchiveAttachmentSupplement.Failure.invalid }
            close(directory); directory = next
        }
        let fd = openat(directory, parts.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw ArchiveAttachmentSupplement.Failure.invalid }
        let reader = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? reader.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              before.st_size >= 0, UInt64(before.st_size) == source.bytes else { throw ArchiveAttachmentSupplement.Failure.changed }
        let outputFD = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard outputFD >= 0 else { throw ArchiveAttachmentSupplement.Failure.conflict }
        let writer = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        var complete = false
        defer { try? writer.close(); if !complete { try? FileManager.default.removeItem(at: destination) } }
        var digest = SHA256(), bytes: UInt64 = 0
        while let chunk = try ArchiveReadBuffer.read(reader, upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            guard bytes <= source.bytes, UInt64(chunk.count) <= source.bytes - bytes else { throw ArchiveAttachmentSupplement.Failure.changed }
            digest.update(data: chunk); bytes += UInt64(chunk.count)
            try writer.write(contentsOf: chunk)
        }
        var after = stat()
        guard fstat(fd, &after) == 0, bytes == source.bytes,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino, before.st_size == after.st_size,
              digest.finalize().map({ String(format: "%02x", $0) }).joined() == source.sha256 else { throw ArchiveAttachmentSupplement.Failure.changed }
        #if canImport(Darwin)
        guard before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw ArchiveAttachmentSupplement.Failure.changed }
        #else
        guard before.st_mtim.tv_sec == after.st_mtim.tv_sec, before.st_mtim.tv_nsec == after.st_mtim.tv_nsec,
              before.st_ctim.tv_sec == after.st_ctim.tv_sec, before.st_ctim.tv_nsec == after.st_ctim.tv_nsec else { throw ArchiveAttachmentSupplement.Failure.changed }
        #endif
        try writer.synchronize(); try writer.close(); try Task.checkCancellation()
        complete = true
    }
}
