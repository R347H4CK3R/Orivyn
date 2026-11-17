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

/// Preparation only. Never guesses export-manifest formats, MIME types, ownership
/// receipts, or missing paths. Copy and reverify before activating any attachment.
/// The caller serializes a canonical app-private extraction root and preserves
/// originals; external source paths must not be supplied here.
enum ArchiveAttachmentAssociation {
    enum Failure: Error { case invalidPath, invalidEvidence, changedFile, limit, io }
    struct Reference: Sendable { let messageID: UUID; let source: String; let originalJSON: Data }
    struct Mapping: Sendable { let sourceID: String; let relativePath: String }
    struct VerifiedFile: Sendable {
        let root: URL; let relativePath: String; let bytes: UInt64; let sha256: String
        fileprivate init(root: URL, relativePath: String, bytes: UInt64, sha256: String) {
            self.root = root; self.relativePath = relativePath; self.bytes = bytes; self.sha256 = sha256
        }
    }
    /// Opaque original asset; not a ChatAttachment or a claim of media compatibility.
    struct Copy: Sendable { let assetID: UUID; let sourceID: String; let sourceRelativePath: String; let destinationName: String; let bytes: UInt64; let sha256: String }
    struct Association: Sendable { let referenceIndex: Int; let messageID: UUID; let assetID: UUID }
    struct Unresolved: Sendable { let referenceIndex: Int; let reason: String }
    struct Plan: Sendable { let references: [Reference]; let copies: [Copy]; let associations: [Association]; let unresolved: [Unresolved] }

    /// Hashes a regular file through no-follow root-relative directory handles.
    /// Evidence expires if the root is subsequently modified: copying must verify
    /// the expected bytes/hash again. This method never writes or removes files.
    static func verify(root: URL, relativePath: String, bytes: UInt64, sha256: String) throws -> VerifiedFile {
        try Task.checkCancellation()
        guard bytes <= 536_870_912, sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw Failure.invalidEvidence }
        let components = try path(relativePath)
        let root = try canonicalRoot(root)
        var descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.invalidPath }
        defer { _ = close(descriptor) }
        for component in components.dropLast() {
            try Task.checkCancellation()
            let next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw Failure.invalidPath }
            _ = close(descriptor); descriptor = next
        }
        let file = openat(descriptor, components.last!, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw Failure.invalidPath }
        defer { _ = close(file) }
        var before = stat()
        guard fstat(file, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size >= 0,
              UInt64(before.st_size) == bytes else { throw Failure.invalidEvidence }
        let reader = FileHandle(fileDescriptor: file, closeOnDealloc: false)
        var digest = SHA256(), readBytes: UInt64 = 0
        while let chunk = try ArchiveReadBuffer.read(reader, upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            guard readBytes <= bytes, UInt64(chunk.count) <= bytes - readBytes else { throw Failure.changedFile }
            digest.update(data: chunk); readBytes += UInt64(chunk.count)
        }
        var after = stat()
        guard readBytes == bytes, fstat(file, &after) == 0, unchanged(before, after),
              digest.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else { throw Failure.changedFile }
        try Task.checkCancellation()
        return VerifiedFile(root: root, relativePath: relativePath, bytes: bytes, sha256: sha256)
    }

    /// Identities must be persisted and scoped to this archive by the coordinator.
    /// Duplicate mappings/evidence/UUIDs fail closed as unresolved records.
    static func plan(root: URL, references: [Reference], mappings: [Mapping], files: [VerifiedFile], identities: [String: UUID]) throws -> Plan {
        try Task.checkCancellation()
        let root = try canonicalRoot(root)
        guard references.count <= 20_000, mappings.count <= 20_000, files.count <= 20_000, identities.count <= 20_000 else { throw Failure.limit }
        var referenceBytes = 0
        for reference in references {
            guard reference.originalJSON.count <= 1_000_000 else { throw Failure.limit }
            referenceBytes += reference.originalJSON.count
            guard referenceBytes <= 16_000_000 else { throw Failure.limit }
        }
        var mappingBytes = 0, identityBytes = 0
        for mapping in mappings {
            try Task.checkCancellation()
            guard mapping.sourceID.utf8.count <= 4096, mapping.relativePath.utf8.count <= 4096 else { throw Failure.limit }
            mappingBytes += mapping.sourceID.utf8.count + mapping.relativePath.utf8.count
            guard mappingBytes <= 16_000_000 else { throw Failure.limit }
        }
        for key in identities.keys {
            try Task.checkCancellation()
            guard key.utf8.count <= 4096 else { throw Failure.limit }
            identityBytes += key.utf8.count
            guard identityBytes <= 16_000_000 else { throw Failure.limit }
        }
        let byID = Dictionary(grouping: mappings, by: \.sourceID)
        let byPath = Dictionary(grouping: files, by: \.relativePath)
        let idCounts = Dictionary(grouping: identities.values, by: { $0 }).mapValues(\.count)
        var copies: [Copy] = [], associations: [Association] = [], unresolved: [Unresolved] = [], copied = Set<String>()
        for (index, reference) in references.enumerated() {
            try Task.checkCancellation()
            func omit(_ reason: String) { unresolved.append(.init(referenceIndex: index, reason: reason)) }
            guard let sourceID = sourceID(reference) else { omit("Unsupported reference record"); continue }
            guard let matches = byID[sourceID], matches.count == 1 else { omit("Missing or ambiguous explicit mapping"); continue }
            let mapping = matches[0]
            guard (try? path(mapping.relativePath)) != nil,
                  let evidence = byPath[mapping.relativePath], evidence.count == 1,
                  evidence[0].root == root else { omit("Missing or ambiguous verified file evidence"); continue }
            guard let id = identities[sourceID], idCounts[id] == 1 else { omit("Missing or ambiguous durable asset identity"); continue }
            let file = evidence[0]
            if copied.insert(sourceID).inserted {
                copies.append(.init(assetID: id, sourceID: sourceID, sourceRelativePath: file.relativePath,
                    destinationName: id.uuidString + ".archive-asset", bytes: file.bytes, sha256: file.sha256))
            }
            associations.append(.init(referenceIndex: index, messageID: reference.messageID, assetID: id))
        }
        return Plan(references: references, copies: copies, associations: associations, unresolved: unresolved)
    }
    private static func sourceID(_ reference: Reference) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: reference.originalJSON) as? [String: Any] else { return nil }
        let key: String
        switch reference.source { case "contentPart": key = "asset_pointer"; case "attachmentMetadata": key = "id"; default: return nil }
        guard let value = object[key] as? String, !value.isEmpty, value.utf8.count <= 4096 else { return nil }
        return value
    }
    private static func path(_ value: String) throws -> [String] {
        guard !value.isEmpty, value.utf8.count <= 4096, !value.hasPrefix("/"), !value.contains("\\"),
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw Failure.invalidPath }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 64, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else { throw Failure.invalidPath }
        return parts
    }
    private static func canonicalRoot(_ root: URL) throws -> URL {
        // URL equality includes representation details (notably the directory
        // hint/trailing slash), which Foundation may change when resolving a
        // directory on Darwin. Validate the physical path instead, then return
        // one representation for exact evidence-root equality in plan().
        let physicalPath = root.path
        guard root.isFileURL, !physicalPath.contains("\0"),
              root.standardizedFileURL.path == physicalPath,
              root.resolvingSymlinksInPath().path == physicalPath else { throw Failure.invalidPath }
        return URL(fileURLWithPath: physicalPath, isDirectory: true)
    }
    private static func unchanged(_ a: stat, _ b: stat) -> Bool {
        guard a.st_dev == b.st_dev, a.st_ino == b.st_ino, a.st_size == b.st_size else { return false }
        #if canImport(Darwin)
        return a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
        #else
        return a.st_mtim.tv_sec == b.st_mtim.tv_sec && a.st_mtim.tv_nsec == b.st_mtim.tv_nsec && a.st_ctim.tv_sec == b.st_ctim.tv_sec && a.st_ctim.tv_nsec == b.st_ctim.tv_nsec
        #endif
    }
}
