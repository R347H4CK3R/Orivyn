import Foundation
import CryptoKit
import Darwin

struct VMCheckpointIdentity: Codable, Equatable, Sendable {
    let engineSHA256: String
    let guestSHA256: String
    let configurationSHA256: String
    var isValid: Bool { [engineSHA256, guestSHA256, configurationSHA256].allSatisfy(VMCheckpointStore.validDigest) }
}

struct VMCheckpointMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generation: UUID
    let identity: VMCheckpointIdentity
    let bytes: Int
    let sha256: String
    let previousGeneration: UUID?
}

enum VMCheckpointError: Error { case rejected, staleTransaction, busy, io, corrupt, incompatible, insufficientSpace }

/// Private, app-owned checkpoint bytes only. No guest commands, paths or network.
/// Call prune() only after a successful save acknowledgement; current, previous
/// and active restore generations are always retained.
actor VMCheckpointStore {
    static let chunkBytes = 128 * 1024
    static let maximumBytes = 256 * 1024 * 1024
    private static let metadataLimit = 4096
    private final class Descriptor: @unchecked Sendable {
        let raw: Int32
        init(_ raw: Int32) throws { guard raw >= 0 else { throw VMCheckpointError.io }; self.raw = raw }
        deinit { Darwin.close(raw) }
    }
    private struct Transaction {
        let id: UUID
        let directory: Descriptor
        let state: Descriptor
        let identity: VMCheckpointIdentity
        let bytes: Int
        let expectedHash: String?
        var offset = 0
        var hasher = SHA256()
    }
    private struct Fingerprint: Equatable {
        let device: Int32
        let inode: UInt64
        let bytes: Int64
        let modifiedSeconds: Int
        let modifiedNanos: Int
        let changedSeconds: Int
        let changedNanos: Int
        init(_ value: stat) {
            device = value.st_dev; inode = value.st_ino; bytes = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
        }
    }
    private struct Lease {
        let metadata: VMCheckpointMetadata
        let directory: Descriptor
        let state: Descriptor
        let fingerprint: Fingerprint
    }
    private let root: Descriptor
    private var transaction: Transaction?
    private var lease: Lease?

    /// Root must already be an app-private directory. Pin its descriptor rather
    /// than repeatedly resolving filesystem paths (the final root cannot be a symlink).
    init(root url: URL) throws {
        guard url.isFileURL, url.standardizedFileURL.path == url.path else { throw VMCheckpointError.rejected }
        root = try Descriptor(Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        let value = try Self.information(root)
        guard (value.st_mode & S_IFMT) == S_IFDIR else { throw VMCheckpointError.rejected }
    }
    static func validDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    func begin(identity: VMCheckpointIdentity, expectedBytes: Int, expectedSHA256: String? = nil) throws -> UUID {
        guard transaction == nil else { throw VMCheckpointError.busy }
        guard identity.isValid, expectedBytes > 0, expectedBytes <= Self.maximumBytes,
              expectedSHA256 == nil || Self.validDigest(expectedSHA256!) else { throw VMCheckpointError.rejected }
        var space = statfs()
        guard fstatfs(root.raw, &space) == 0, space.f_bsize > 0 else { throw VMCheckpointError.io }
        let reserve = UInt64(expectedBytes) + 4 * 1024 * 1024
        let blockSize = UInt64(space.f_bsize)
        guard UInt64(space.f_bavail) >= (reserve + blockSize - 1) / blockSize else { throw VMCheckpointError.insufficientSpace }
        let id = UUID(), name = "s-" + id.uuidString
        guard mkdirat(root.raw, name, 0o700) == 0 else { throw VMCheckpointError.io }
        do {
            let directory = try Self.openDirectory(root, name)
            let state = try Descriptor(openat(directory.raw, "state.bin", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600))
            transaction = Transaction(id: id, directory: directory, state: state, identity: identity, bytes: expectedBytes, expectedHash: expectedSHA256)
            return id
        } catch {
            // Only this newly created staging directory is eligible for cleanup.
            _ = unlinkat(root.raw, name, AT_REMOVEDIR)
            throw error
        }
    }
    @discardableResult
    func append(transaction id: UUID, offset: Int, data: Data) throws -> Int {
        guard var current = transaction, current.id == id else { throw VMCheckpointError.staleTransaction }
        guard !data.isEmpty, data.count <= Self.chunkBytes, offset == current.offset,
              data.count <= current.bytes - current.offset else { throw VMCheckpointError.rejected }
        try Self.writeAll(current.state, data: data, offset: offset)
        current.hasher.update(data: data); current.offset += data.count
        transaction = current
        return current.offset
    }
    func commit(transaction id: UUID) throws -> VMCheckpointMetadata {
        guard let current = transaction, current.id == id else { throw VMCheckpointError.staleTransaction }
        guard current.offset == current.bytes else { throw VMCheckpointError.rejected }
        let namedDirectory = try Self.openDirectory(root, "s-" + id.uuidString)
        let heldDirectoryInfo = try Self.information(current.directory)
        let namedDirectoryInfo = try Self.information(namedDirectory)
        guard heldDirectoryInfo.st_dev == namedDirectoryInfo.st_dev,
              heldDirectoryInfo.st_ino == namedDirectoryInfo.st_ino else { throw VMCheckpointError.corrupt }
        let namedState = try Descriptor(openat(current.directory.raw, "state.bin", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK))
        guard Fingerprint(try Self.information(namedState)) == Fingerprint(try Self.information(current.state)) else { throw VMCheckpointError.corrupt }
        guard fsync(current.state.raw) == 0 else { throw VMCheckpointError.io }
        var finalHasher = current.hasher
        let streamedHash = Self.hex(finalHasher.finalize())
        guard current.expectedHash == nil || current.expectedHash == streamedHash else { throw VMCheckpointError.corrupt }
        let diskHash = try Self.hash(current.state, bytes: current.bytes)
        guard diskHash == streamedHash else { throw VMCheckpointError.corrupt }
        let previous = try pointerMetadata()
        if let previous { guard try load(identity: previous.identity, generation: previous.generation).metadata == previous else { throw VMCheckpointError.corrupt } }
        let metadata = VMCheckpointMetadata(schemaVersion: 1, generation: id, identity: current.identity, bytes: current.bytes, sha256: diskHash, previousGeneration: previous?.generation)
        let encoded = try JSONEncoder().encode(metadata)
        guard encoded.count <= Self.metadataLimit else { throw VMCheckpointError.rejected }
        // Metadata is prepared inside the staging directory, not in the current generation.
        try Self.writeNew(current.directory, name: "metadata.json", data: encoded)
        guard fsync(current.directory.raw) == 0 else { throw VMCheckpointError.io }
        guard renameat(root.raw, "s-" + id.uuidString, root.raw, "g-" + id.uuidString) == 0 else { throw VMCheckpointError.io }
        // Once renamed, this immutable generation may be orphaned by interruption,
        // but no previously published checkpoint has been replaced yet.
        transaction = nil
        let pointerName = ".current-" + id.uuidString
        do {
            try Self.writeNew(root, name: pointerName, data: encoded)
            guard renameat(root.raw, pointerName, root.raw, "current.json") == 0 else { throw VMCheckpointError.io }
            guard fsync(root.raw) == 0 else { throw VMCheckpointError.io }
        } catch { _ = unlinkat(root.raw, pointerName, 0); throw error }
        return metadata
    }
    func abort(transaction id: UUID) throws {
        guard let current = transaction, current.id == id else { throw VMCheckpointError.staleTransaction }
        transaction = nil
        // unlinkat never follows a symlink; these names are not guest supplied.
        _ = unlinkat(current.directory.raw, "state.bin", 0)
        _ = unlinkat(current.directory.raw, "metadata.json", 0)
        guard unlinkat(root.raw, "s-" + id.uuidString, AT_REMOVEDIR) == 0 else { throw VMCheckpointError.io }
    }
    func latest(identity: VMCheckpointIdentity) throws -> VMCheckpointMetadata? {
        guard identity.isValid else { throw VMCheckpointError.rejected }
        lease = nil
        guard let pointer = try pointerMetadata() else { return nil }
        guard pointer.identity == identity else { throw VMCheckpointError.incompatible }
        let verified = try load(identity: identity, generation: pointer.generation)
        guard pointer == verified.metadata else { throw VMCheckpointError.corrupt }
        lease = verified
        return verified.metadata
    }
    /// A generation is mandatory so a concurrent save cannot mix restore chunks.
    func read(identity: VMCheckpointIdentity, generation: UUID, offset: Int, length: Int) throws -> Data {
        guard identity.isValid, offset >= 0, length > 0, length <= Self.chunkBytes else { throw VMCheckpointError.rejected }
        if lease?.metadata.generation != generation || lease?.metadata.identity != identity {
            lease = try load(identity: identity, generation: generation)
        }
        guard let lease, offset <= lease.metadata.bytes, length <= lease.metadata.bytes - offset else { throw VMCheckpointError.rejected }
        guard Fingerprint(try Self.information(lease.state)) == lease.fingerprint else { self.lease = nil; throw VMCheckpointError.corrupt }
        let data = try Self.readExactly(lease.state, offset: offset, count: length)
        guard Fingerprint(try Self.information(lease.state)) == lease.fingerprint else { self.lease = nil; throw VMCheckpointError.corrupt }
        return data
    }
    /// Explicit housekeeping after successful publication. Unknown/corrupt data is
    /// not erased; only fully verified owned generations older than the prior save.
    @discardableResult
    func prune() throws -> Int {
        guard let current = try pointerMetadata() else { return 0 }
        guard try load(identity: current.identity, generation: current.generation).metadata == current else { throw VMCheckpointError.corrupt }
        var keep: Set<UUID> = [current.generation]
        if let previous = current.previousGeneration {
            let directory = try Self.openDirectory(root, "g-" + previous.uuidString)
            let descriptor = try Descriptor(openat(directory.raw, "metadata.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK))
            let metadata = try Self.decode(Self.readBounded(descriptor, limit: Self.metadataLimit))
            _ = try load(identity: metadata.identity, generation: previous)
            keep.insert(previous)
        }
        if let active = lease?.metadata.generation { keep.insert(active) }
        if let active = transaction?.id { keep.insert(active) }
        var removed = 0
        for name in try Self.names(root) {
            guard name.hasPrefix("g-"), let id = UUID(uuidString: String(name.dropFirst(2))),
                  name == "g-" + id.uuidString, !keep.contains(id) else { continue }
            // A corrupt or foreign directory is retained for explicit recovery.
            guard let directory = try? Self.openDirectory(root, name),
                  let contents = try? Self.names(directory), Set(contents) == ["state.bin", "metadata.json"],
                  let descriptor = try? Descriptor(openat(directory.raw, "metadata.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)),
                  let data = try? Self.readBounded(descriptor, limit: Self.metadataLimit),
                  let metadata = try? Self.decode(data), metadata.generation == id,
                  (try? load(identity: metadata.identity, generation: id)) != nil else { continue }
            guard unlinkat(directory.raw, "state.bin", 0) == 0,
                  unlinkat(directory.raw, "metadata.json", 0) == 0,
                  unlinkat(root.raw, name, AT_REMOVEDIR) == 0 else { throw VMCheckpointError.io }
            removed += 1
        }
        if removed > 0 { guard fsync(root.raw) == 0 else { throw VMCheckpointError.io } }
        return removed
    }
    private func pointerMetadata() throws -> VMCheckpointMetadata? {
        let fd = openat(root.raw, "current.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 && errno == ENOENT { return nil }
        return try Self.decode(Self.readBounded(Descriptor(fd), limit: Self.metadataLimit))
    }
    private static func names(_ parent: Descriptor) throws -> [String] {
        let fd = openat(parent.raw, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw VMCheckpointError.io }
        guard let stream = fdopendir(fd) else { Darwin.close(fd); throw VMCheckpointError.io }
        defer { closedir(stream) }
        var result: [String] = []
        errno = 0
        while let entry = readdir(stream) {
            var bytes = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: bytes)
            let name = withUnsafePointer(to: &bytes) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
            }
            if name != "." && name != ".." { result.append(name) }
            guard result.count <= 1024 else { throw VMCheckpointError.rejected }
            errno = 0
        }
        guard errno == 0 else { throw VMCheckpointError.io }
        return result
    }
    private func load(identity: VMCheckpointIdentity, generation: UUID) throws -> Lease {
        let directory = try Self.openDirectory(root, "g-" + generation.uuidString)
        let metadataFile = try Descriptor(openat(directory.raw, "metadata.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK))
        let metadata = try Self.decode(Self.readBounded(metadataFile, limit: Self.metadataLimit))
        guard metadata.generation == generation, metadata.identity == identity else { throw VMCheckpointError.incompatible }
        let state = try Descriptor(openat(directory.raw, "state.bin", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK))
        let before = Fingerprint(try Self.information(state))
        guard try Self.hash(state, bytes: metadata.bytes) == metadata.sha256,
              Fingerprint(try Self.information(state)) == before else { throw VMCheckpointError.corrupt }
        return Lease(metadata: metadata, directory: directory, state: state, fingerprint: before)
    }
    private static func decode(_ data: Data) throws -> VMCheckpointMetadata {
        guard let value = try? JSONDecoder().decode(VMCheckpointMetadata.self, from: data),
              value.schemaVersion == 1, value.identity.isValid, value.bytes > 0,
              value.bytes <= maximumBytes, value.previousGeneration != value.generation, validDigest(value.sha256) else { throw VMCheckpointError.corrupt }
        return value
    }
    private static func openDirectory(_ parent: Descriptor, _ name: String) throws -> Descriptor {
        try Descriptor(openat(parent.raw, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
    }
    private static func information(_ fd: Descriptor) throws -> stat {
        var value = stat(); guard fstat(fd.raw, &value) == 0 else { throw VMCheckpointError.io }; return value
    }
    private static func readBounded(_ fd: Descriptor, limit: Int) throws -> Data {
        let value = try information(fd)
        guard (value.st_mode & S_IFMT) == S_IFREG, value.st_size > 0, value.st_size <= Int64(limit) else { throw VMCheckpointError.rejected }
        return try readExactly(fd, offset: 0, count: Int(value.st_size))
    }
    private static func readExactly(_ fd: Descriptor, offset: Int, count: Int) throws -> Data {
        var data = Data(count: count), consumed = 0
        while consumed < count {
            let amount = data.withUnsafeMutableBytes { bytes in pread(fd.raw, bytes.baseAddress!.advanced(by: consumed), count - consumed, off_t(offset + consumed)) }
            if amount < 0 && errno == EINTR { continue }
            guard amount > 0 else { throw VMCheckpointError.io }; consumed += amount
        }
        return data
    }
    private static func writeAll(_ fd: Descriptor, data: Data, offset: Int) throws {
        var written = 0
        while written < data.count {
            let amount = data.withUnsafeBytes { bytes in pwrite(fd.raw, bytes.baseAddress!.advanced(by: written), data.count - written, off_t(offset + written)) }
            if amount < 0 && errno == EINTR { continue }
            guard amount > 0 else { throw VMCheckpointError.io }; written += amount
        }
    }
    private static func writeNew(_ parent: Descriptor, name: String, data: Data) throws {
        let fd = try Descriptor(openat(parent.raw, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600))
        try writeAll(fd, data: data, offset: 0)
        guard fsync(fd.raw) == 0 else { throw VMCheckpointError.io }
    }
    private static func hash(_ fd: Descriptor, bytes: Int) throws -> String {
        let value = try information(fd)
        guard (value.st_mode & S_IFMT) == S_IFREG, value.st_size == Int64(bytes), bytes > 0, bytes <= maximumBytes else { throw VMCheckpointError.corrupt }
        var hasher = SHA256(), offset = 0
        while offset < bytes {
            let count = min(chunkBytes, bytes - offset)
            hasher.update(data: try readExactly(fd, offset: offset, count: count)); offset += count
        }
        return hex(hasher.finalize())
    }
    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
}
