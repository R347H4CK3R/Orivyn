import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Owns only a private temporary model copy, never the installed source model.
/// Advisory locks protect cooperating app instances; malformed/unowned entries
/// are retained. Destruction must occur after all mmap/model references release.
final class NativeModelSnapshot: @unchecked Sendable {
    static let prefix = "OrivynNativeModel-v1-"
    private static let marker = Array("OrivynNativeSnapshot/v1\n".utf8)
    let directory: URL
    var modelURL: URL { directory.appendingPathComponent("model.gguf") }
    private let rootFD: Int32
    private let directoryFD: Int32
    private let leaseFD: Int32
    private let name: String
    private init(root: URL, name: String, rootFD: Int32, directoryFD: Int32, leaseFD: Int32) {
        directory = root.appendingPathComponent(name, isDirectory: true)
        self.name = name; self.rootFD = rootFD; self.directoryFD = directoryFD; self.leaseFD = leaseFD
    }
    deinit {
        _ = Self.removeOwned(rootFD: rootFD, name: name, directoryFD: directoryFD, leaseFD: leaseFD)
        close(leaseFD); close(directoryFD); close(rootFD)
    }
    static func create(in root: URL) throws -> NativeModelSnapshot {
        try withRoot(root) { rootFD, coordinationFD in
            _ = sweep(root: root, rootFD: rootFD, coordinationFD: coordinationFD)
            let name = prefix + UUID().uuidString
            guard mkdirat(rootFD, name, 0o700) == 0 else { throw failure() }
            let directoryFD = openat(rootFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directoryFD >= 0 else { throw failure() }
            var retained = false
            defer { if !retained { close(directoryFD); _ = unlinkat(rootFD, name, AT_REMOVEDIR) } }
            let leaseFD = openat(directoryFD, "owner.lock", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard leaseFD >= 0 else { throw failure() }
            defer { if !retained { close(leaseFD); _ = unlinkat(directoryFD, "owner.lock", 0) } }
            guard flock(leaseFD, LOCK_EX | LOCK_NB) == 0,
                  marker.withUnsafeBytes({ write(leaseFD, $0.baseAddress, $0.count) }) == marker.count,
                  fsync(leaseFD) == 0 else { throw failure() }
            let ownedRoot = dup(rootFD)
            guard ownedRoot >= 0 else { throw failure() }
            retained = true
            return NativeModelSnapshot(root: root, name: name, rootFD: ownedRoot, directoryFD: directoryFD, leaseFD: leaseFD)
        }
    }
    @discardableResult static func cleanup(in root: URL) throws -> Int {
        try withRoot(root) { sweep(root: root, rootFD: $0, coordinationFD: $1) }
    }
    private static func withRoot<T>(_ root: URL, body: (Int32, Int32) throws -> T) throws -> T {
        guard root.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure() }
        defer { close(fd) }
        let lock = openat(fd, ".orivyn-native-snapshot-v1.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard lock >= 0 else { throw failure() }
        defer { close(lock) }
        guard regularOwned(lock), flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw failure() }
        return try body(fd, lock)
    }
    private static func sweep(root: URL, rootFD: Int32, coordinationFD: Int32) -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return 0 }
        // Root enumeration is not bounded. At most 128 candidate directories are
        // inspected per pass, with a durable rotating cursor so preserved entries
        // do not permanently starve later names. Malformed cursor data is retained.
        var cursorBytes = [UInt8](repeating: 0, count: 128)
        let count = pread(coordinationFD, &cursorBytes, cursorBytes.count, 0)
        guard count >= 0, count < cursorBytes.count else { return 0 }
        let cursor = String(decoding: cursorBytes.prefix(count), as: UTF8.self)
        guard cursor.isEmpty || validName(cursor) else { return 0 }
        let sorted = names.filter { validName($0) }.sorted()
        let ordered = sorted.filter { $0 > cursor } + sorted.filter { $0 <= cursor }
        let batch = Array(ordered.prefix(128))
        guard let last = batch.last else { return 0 }
        let next = Array(last.utf8)
        guard next.withUnsafeBytes({ pwrite(coordinationFD, $0.baseAddress, $0.count, 0) }) == next.count,
              ftruncate(coordinationFD, off_t(next.count)) == 0, fsync(coordinationFD) == 0 else { return 0 }
        var removed = 0
        for name in batch {
            let dir = openat(rootFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard dir >= 0 else { continue }
            defer { close(dir) }
            let lock = openat(dir, "owner.lock", O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard lock >= 0 else { continue }
            defer { close(lock) }
            guard regularOwned(lock), flock(lock, LOCK_EX | LOCK_NB) == 0 else { continue }
            if removeOwned(rootFD: rootFD, name: name, directoryFD: dir, leaseFD: lock) { removed += 1 }
        }
        return removed
    }
    private static func validName(_ name: String) -> Bool {
        guard name.hasPrefix(prefix) else { return false }
        let suffix = String(name.dropFirst(prefix.count))
        return UUID(uuidString: suffix)?.uuidString == suffix
    }
    private static func regularOwned(_ fd: Int32) -> Bool {
        var s = stat()
        return fstat(fd, &s) == 0 && (s.st_mode & S_IFMT) == S_IFREG && s.st_uid == geteuid() && s.st_nlink == 1
    }
    private static func sameEntry(_ fd: Int32, parent: Int32, name: String) -> Bool {
        var a = stat(), b = stat()
        return fstat(fd, &a) == 0 && fstatat(parent, name, &b, AT_SYMLINK_NOFOLLOW) == 0 && a.st_dev == b.st_dev && a.st_ino == b.st_ino
    }
    private static func removeOwned(rootFD: Int32, name: String, directoryFD: Int32, leaseFD: Int32) -> Bool {
        guard validName(name), regularOwned(leaseFD), sameEntry(directoryFD, parent: rootFD, name: name),
              sameEntry(leaseFD, parent: directoryFD, name: "owner.lock") else { return false }
        var dirStat = stat()
        guard fstat(directoryFD, &dirStat) == 0, dirStat.st_uid == geteuid(), (dirStat.st_mode & 0o777) == 0o700 else { return false }
        var bytes = [UInt8](repeating: 0, count: marker.count + 1)
        let length = pread(leaseFD, &bytes, bytes.count, 0)
        guard length == marker.count, Array(bytes.prefix(length)) == marker else { return false }
        // Enumerate the opened directory, not a mutable pathname. No recursion.
        let duplicate = dup(directoryFD)
        guard duplicate >= 0, let stream = fdopendir(duplicate) else { if duplicate >= 0 { close(duplicate) }; return false }
        var names = Set<String>()
        errno = 0
        while let entry = readdir(stream) {
            let value = withUnsafePointer(to: &entry.pointee.d_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) { String(cString: $0) }
            }
            if value != "." && value != ".." { names.insert(value) }
        }
        let enumerationError = errno
        closedir(stream)
        guard enumerationError == 0 else { return false }
        guard names == ["owner.lock"] || names == ["owner.lock", "model.gguf"] else { return false }
        if names.contains("model.gguf") {
            let model = openat(directoryFD, "model.gguf", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard model >= 0 else { return false }
            defer { close(model) }
            guard regularOwned(model), sameEntry(model, parent: directoryFD, name: "model.gguf"),
                  unlinkat(directoryFD, "model.gguf", 0) == 0 else { return false }
        }
        guard unlinkat(directoryFD, "owner.lock", 0) == 0 else { return false }
        return unlinkat(rootFD, name, AT_REMOVEDIR) == 0
    }
    private static func failure() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
