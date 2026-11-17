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

/// Original-byte preservation only; no ZIP parsing or history activation. The
/// staging parent must be a canonical app-private directory owned by the coordinator.
/// Ancestors must not be concurrently replaced. The caller coordinates external
/// provider access; O_NOFOLLOW protects final components, not arbitrary ancestor races.
/// Failures retain partial files for diagnosis; nothing here deletes the source.
enum ArchivePreservation {
    struct Manifest: Codable, Equatable, Sendable {
        let version: Int
        let bytes: UInt64
        let sha256: String
    }
    enum Failure: LocalizedError {
        case invalidPath, notRegularFile, limit, insufficientSpace, io, changedSource, verification, invalidManifest
        var errorDescription: String? {
            switch self {
            case .insufficientSpace: return "There is not enough free storage to preserve this ZIP safely. Free space for a complete ZIP copy and its extracted files, then try again."
            case .limit: return "This ZIP exceeds the supported archive size. Try a smaller export."
            case .invalidPath, .notRegularFile: return "The selected archive is not a safe regular file. Select a local ZIP file and try again."
            case .changedSource: return "The source ZIP changed during verification. Wait for its download to finish and try again."
            case .verification, .invalidManifest: return "The preserved ZIP could not be verified. No unverified archive will be imported."
            case .io: return "The archive could not be read or saved. Check available storage and file access, then try again."
            }
        }
    }
    private static let chunk = 65_536
    private static let reserve: UInt64 = 33_554_432

    static func preserve(source: URL, staging: URL, maximumBytes: UInt64 = 8_589_934_592,
                         progress: (String, UInt64) throws -> Void = { _, _ in }) throws -> Manifest {
        try Task.checkCancellation()
        try plainPath(source)
        try plainPath(staging.deletingLastPathComponent())
        let sourceFD = try openRegular(source, maximumBytes: maximumBytes)
        defer { _ = close(sourceFD) }
        let before = try attributes(sourceFD)
        let size = UInt64(before.st_size)
        let parent = staging.deletingLastPathComponent()
        let available = try freeBytes(parent)
        guard size <= UInt64.max - reserve, available >= size + reserve else { throw Failure.insufficientSpace }
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { throw Failure.invalidPath }
        defer { _ = close(parentFD) }
        // mkdirat is exclusive. An existing file/directory/symlink is never reused.
        let name = staging.lastPathComponent
        guard staging.isFileURL, name != ".", name != "..", !name.isEmpty,
              mkdirat(parentFD, name, 0o700) == 0 else { throw Failure.invalidPath }
        let directory = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw Failure.io }
        defer { _ = close(directory) }
        let output = openat(directory, "original.zip", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw Failure.io }
        defer { _ = close(output) }
        var hash = SHA256(), copied: UInt64 = 0
        let input = FileHandle(fileDescriptor: sourceFD, closeOnDealloc: false)
        while true {
            try Task.checkCancellation()
            guard let data = try ArchiveReadBuffer.read(input, upToCount: chunk), !data.isEmpty else { break }
            guard copied <= size, UInt64(data.count) <= size - copied else { throw Failure.changedSource }
            try writeAll(data, to: output)
            hash.update(data: data); copied += UInt64(data.count)
            try progress("copy", copied)
        }
        guard copied == size, fsync(output) == 0 else { throw Failure.io }
        let manifest = Manifest(version: 1, bytes: size, sha256: hex(hash.finalize()))
        guard try digest(output, expectedSize: size, progress: { try progress("verify-copy", $0) }) == manifest.sha256 else { throw Failure.verification }
        guard try digest(sourceFD, expectedSize: size, progress: { try progress("verify-source", $0) }) == manifest.sha256,
              sameSource(before, try attributes(sourceFD)) else { throw Failure.changedSource }
        try Task.checkCancellation()
        // Only publish completion metadata after all copied bytes and the source
        // have been read again. Incomplete jobs have no verified manifest.
        let data = try JSONEncoder().encode(manifest)
        let manifestFD = openat(directory, "verified-manifest.json.partial", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard manifestFD >= 0 else { throw Failure.io }
        defer { _ = close(manifestFD) }
        try writeAll(data, to: manifestFD)
        guard fsync(manifestFD) == 0 else { throw Failure.io }
        try Task.checkCancellation()
        guard linkat(directory, "verified-manifest.json.partial", directory, "verified-manifest.json", 0) == 0,
              fsync(directory) == 0, fsync(parentFD) == 0 else { throw Failure.io }
        // Retain the partial hard link too: it is tiny and avoids cleanup side effects.
        return manifest
    }

    /// The manifest is an integrity record, not an authenticity signature. Keep
    /// staging app-private. A caller with a durable expected manifest should pass it.
    static func revalidate(staging: URL, expected: Manifest? = nil,
                           maximumBytes: UInt64 = 8_589_934_592) throws -> Manifest {
        try Task.checkCancellation()
        try plainPath(staging)
        let manifestFD = try openRegular(staging.appendingPathComponent("verified-manifest.json"), maximumBytes: 4096)
        defer { _ = close(manifestFD) }
        let handle = FileHandle(fileDescriptor: manifestFD, closeOnDealloc: false)
        guard let data = try handle.read(upToCount: 4097), data.count <= 4096,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.version == 1, manifest.bytes <= maximumBytes,
              manifest.sha256.count == 64,
              manifest.sha256.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (97...102).contains($0.value) }),
              expected == nil || expected == manifest else { throw Failure.invalidManifest }
        let archiveFD = try openRegular(staging.appendingPathComponent("original.zip"), maximumBytes: maximumBytes)
        defer { _ = close(archiveFD) }
        let before = try attributes(archiveFD)
        guard try digest(archiveFD, expectedSize: manifest.bytes) == manifest.sha256,
              sameSource(before, try attributes(archiveFD)) else { throw Failure.verification }
        return manifest
    }

    private static func plainPath(_ url: URL) throws {
        guard url.isFileURL, url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else { throw Failure.invalidPath }
    }
    private static func openRegular(_ url: URL, maximumBytes: UInt64) throws -> Int32 {
        try plainPath(url)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.io }
        do {
            let info = try attributes(fd)
            guard info.st_size >= 0, UInt64(info.st_size) <= maximumBytes else { throw Failure.limit }
            return fd
        } catch { _ = close(fd); throw error }
    }
    private static func attributes(_ fd: Int32) throws -> stat {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw Failure.io }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw Failure.notRegularFile }
        return info
    }
    private static func sameSource(_ a: stat, _ b: stat) -> Bool {
        #if canImport(Darwin)
        let timesMatch = a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
        #else
        let timesMatch = a.st_mtim.tv_sec == b.st_mtim.tv_sec && a.st_mtim.tv_nsec == b.st_mtim.tv_nsec
        #endif
        return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size && timesMatch
    }
    private static func freeBytes(_ directory: URL) throws -> UInt64 {
        var info = statvfs()
        guard statvfs(directory.path, &info) == 0 else { throw Failure.io }
        let (bytes, overflow) = UInt64(info.f_bavail).multipliedReportingOverflow(by: UInt64(info.f_frsize))
        guard !overflow else { throw Failure.limit }
        return bytes
    }
    private static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure.io }
                offset += count
            }
        }
    }
    private static func digest(_ fd: Int32, expectedSize: UInt64,
                               progress: (UInt64) throws -> Void = { _ in }) throws -> String {
        guard lseek(fd, 0, SEEK_SET) == 0, UInt64(try attributes(fd).st_size) == expectedSize else { throw Failure.verification }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var hash = SHA256(), count: UInt64 = 0
        while true {
            try Task.checkCancellation()
            guard let data = try ArchiveReadBuffer.read(handle, upToCount: chunk), !data.isEmpty else { break }
            guard count <= expectedSize, UInt64(data.count) <= expectedSize - count else { throw Failure.verification }
            hash.update(data: data); count += UInt64(data.count)
            try progress(count)
        }
        guard count == expectedSize else { throw Failure.verification }
        return hex(hash.finalize())
    }
    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
}
