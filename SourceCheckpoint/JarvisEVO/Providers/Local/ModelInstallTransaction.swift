import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Synchronous, single-owner two-file publication with restart rollback. The prepared
/// marker is removed only after both renames. This handles process interruption, not
/// a guarantee against filesystem/media failure or sudden power-loss write reordering.
enum ModelInstallTransaction {
    enum Publication: Equatable { case model, manifest }
    enum Failure: Error, LocalizedError {
        case invalidState, recoveryRequired
        var errorDescription: String? {
            switch self {
            case .invalidState: "Model storage is invalid. Existing files have been retained."
            case .recoveryRequired: "Model storage recovery is incomplete. Recovery files are retained; reopen the app to retry."
            }
        }
    }
    private struct Journal: Codable {
        let targetName: String
        let hadModel: Bool
        let hadManifest: Bool
        let version: Int
    }
    private static let folder = ".model-install-transaction"
    private static let manifestName = "installed-models.json"
    private static let fm = FileManager.default

    static func commit(root: URL, targetName: String, source: URL, manifest: Data,
                       prepareFile: (URL) throws -> Void = { _ in },
                       didPublish: (Publication) throws -> Void = { _ in }) throws {
        try mutate(root: root, targetName: targetName, source: source, manifest: manifest,
                   prepareFile: prepareFile, didPublish: didPublish)
    }

    static func remove(root: URL, targetName: String, manifest: Data,
                       prepareFile: (URL) throws -> Void = { _ in },
                       didPublish: (Publication) throws -> Void = { _ in }) throws {
        try mutate(root: root, targetName: targetName, source: nil, manifest: manifest,
                   prepareFile: prepareFile, didPublish: didPublish)
    }

    private static func mutate(root: URL, targetName: String, source: URL?, manifest: Data,
                               prepareFile: (URL) throws -> Void,
                               didPublish: (Publication) throws -> Void) throws {
        guard validName(targetName) else { throw Failure.invalidState }
        try recover(root: root)
        let target = root.appendingPathComponent(targetName)
        let manifestURL = root.appendingPathComponent(manifestName)
        let hadModel = try regularFileExists(target)
        let hadManifest = try regularFileExists(manifestURL)
        if let source, try !regularFileExists(source) { throw Failure.invalidState }
        let directory = root.appendingPathComponent(folder, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        let marker = directory.appendingPathComponent("prepared.json")
        do {
            let newModel = directory.appendingPathComponent("new-model")
            let newManifest = directory.appendingPathComponent("new-manifest")
            if let source { try fm.copyItem(at: source, to: newModel) }
            try manifest.write(to: newManifest, options: .atomic)
            if source != nil { try prepareFile(newModel) }
            try prepareFile(newManifest)
            // Immutable copies survive replacement of either live destination.
            if hadModel { try fm.copyItem(at: target, to: directory.appendingPathComponent("old-model")) }
            if hadManifest { try fm.copyItem(at: manifestURL, to: directory.appendingPathComponent("old-manifest")) }
            try Task.checkCancellation()
            let journal = Journal(targetName: targetName, hadModel: hadModel, hadManifest: hadManifest, version: 1)
            try JSONEncoder().encode(journal).write(to: marker, options: .atomic)
            if source != nil { try atomicRename(newModel, target) }
            else if hadModel { try fm.removeItem(at: target) }
            try didPublish(.model)
            try atomicRename(newManifest, manifestURL)
            try didPublish(.manifest)
            // Commit point. Failure here must roll back, never discard recovery copies.
            try fm.removeItem(at: marker)
        } catch {
            let original = error
            do { try recover(root: root) }
            catch { throw Failure.recoveryRequired }
            throw original
        }
        // If cleanup fails, next recovery sees no prepared marker and removes only staging.
        try? fm.removeItem(at: directory)
    }

    static func recover(root: URL) throws {
        let directory = root.appendingPathComponent(folder, isDirectory: true)
        guard let attributes = try attributesIfPresent(directory) else { return }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw Failure.invalidState }
        let marker = directory.appendingPathComponent("prepared.json")
        guard try regularFileExists(marker) else {
            try fm.removeItem(at: directory)
            return
        }
        let markerAttributes = try fm.attributesOfItem(atPath: marker.path)
        guard let size = markerAttributes[.size] as? NSNumber, size.intValue <= 4_096 else { throw Failure.invalidState }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: marker))
        guard journal.version == 1, validName(journal.targetName) else { throw Failure.invalidState }
        let target = root.appendingPathComponent(journal.targetName)
        let manifest = root.appendingPathComponent(manifestName)
        // Validate all inputs before changing either destination. Incomplete recovery stays blocked.
        _ = try regularFileExists(target); _ = try regularFileExists(manifest)
        if journal.hadModel, try !regularFileExists(directory.appendingPathComponent("old-model")) { throw Failure.invalidState }
        if journal.hadManifest, try !regularFileExists(directory.appendingPathComponent("old-manifest")) { throw Failure.invalidState }
        try restore(hadOriginal: journal.hadModel, backup: directory.appendingPathComponent("old-model"), target: target, scratch: directory.appendingPathComponent("restore-model"))
        try restore(hadOriginal: journal.hadManifest, backup: directory.appendingPathComponent("old-manifest"), target: manifest, scratch: directory.appendingPathComponent("restore-manifest"))
        try fm.removeItem(at: marker)
        try? fm.removeItem(at: directory)
    }

    private static func restore(hadOriginal: Bool, backup: URL, target: URL, scratch: URL) throws {
        if hadOriginal {
            if try regularFileExists(scratch) { try fm.removeItem(at: scratch) }
            try fm.copyItem(at: backup, to: scratch)
            try atomicRename(scratch, target)
        } else if try regularFileExists(target) { try fm.removeItem(at: target) }
    }
    private static func validName(_ name: String) -> Bool {
        name.hasSuffix(".gguf") && name.utf8.count <= 255 && !name.contains("/") && !name.contains("\\") &&
        !name.contains("..") && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    private static func attributesIfPresent(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try fm.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
    }
    private static func regularFileExists(_ url: URL) throws -> Bool {
        guard let attributes = try attributesIfPresent(url) else { return false }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure.invalidState }
        return true
    }
    private static func atomicRename(_ source: URL, _ destination: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else { return Int32(-1) }
                return rename(from, to)
            }
        }
        guard result == 0 else { throw Failure.recoveryRequired }
    }
}
