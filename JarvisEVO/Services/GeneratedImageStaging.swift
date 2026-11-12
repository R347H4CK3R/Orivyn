import Foundation
import Darwin

/// Policy deliberately excludes later systems whose image generation may use cloud models.
enum ImageCreationAvailability {
    static func isAvailable(supportsImagePlayground: Bool, osMajorVersion: Int) -> Bool {
        supportsImagePlayground && osMajorVersion == 26
    }

    static func isValidConcept(_ concept: String) -> Bool {
        !concept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            concept.utf8.count <= 1_024 && !concept.utf8.contains(0)
    }
}

enum GeneratedImageStagingError: LocalizedError {
    case unsafeFile, unsupportedType, invalidSize, unreadableFile, unavailableDirectory

    var errorDescription: String? {
        switch self {
        case .unsafeFile: "The generated image could not be safely accessed. Please try creating it again."
        case .unsupportedType: "The generated file is not a supported PNG, JPEG, HEIC or HEIF image."
        case .invalidSize: "The generated image must be nonempty and no larger than 10 MiB."
        case .unreadableFile: "The generated image could not be read. Please try again."
        case .unavailableDirectory: "Image storage is unavailable. Your description has been kept; please try again."
        }
    }
}

/// Synchronously takes ownership of accepted system output before its temporary URL expires.
/// This is bounded staging, not image validation. AttachmentService must still decode and
/// validate the image before persistence. The callback recipient owns discard after handoff.
struct GeneratedImageStaging: Sendable {
    let directory: URL
    private static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif"]

    init(directory: URL) throws {
        guard directory.isFileURL, !directory.path.utf8.contains(0) else { throw GeneratedImageStagingError.unsafeFile }
        let path = directory.standardizedFileURL
        if (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw GeneratedImageStagingError.unsafeFile
        }
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        let values = try path.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw GeneratedImageStagingError.unavailableDirectory
        }
        self.directory = path.resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: self.directory.path)
        var ownedDirectory = self.directory
        var backup = URLResourceValues()
        backup.isExcludedFromBackup = true
        try ownedDirectory.setResourceValues(backup)
    }

    func stage(from source: URL) throws -> URL {
        guard source.isFileURL, !source.path.utf8.contains(0) else { throw GeneratedImageStagingError.unsafeFile }
        let suffix = source.pathExtension.lowercased()
        guard Self.extensions.contains(suffix) else { throw GeneratedImageStagingError.unsupportedType }
        try validateDirectory()
        // Nonblocking prevents FIFOs from hanging; no-follow rejects final-component symlinks.
        let descriptor = Darwin.open(source.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw GeneratedImageStagingError.unreadableFile }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw GeneratedImageStagingError.unsafeFile
        }
        let limit = AttachmentService.maximumBytes
        guard info.st_size > 0, info.st_size <= off_t(limit) else { throw GeneratedImageStagingError.invalidSize }
        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count <= limit {
            let remaining = min(buffer.count, limit + 1 - data.count)
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, remaining) }
            if count < 0 {
                if errno == EINTR { continue }
                throw GeneratedImageStagingError.unreadableFile
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == Int(info.st_size), data.count <= limit else { throw GeneratedImageStagingError.invalidSize }
        try validateDirectory()
        let destination = directory.appendingPathComponent(UUID().uuidString + "." + suffix)
        do {
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Only the recipient of stage(from:) may discard its owned file. Never sweeps other jobs.
    func discard(_ stagedURL: URL) throws {
        try validateDirectory()
        guard stagedURL.isFileURL, !stagedURL.path.utf8.contains(0),
              stagedURL.standardizedFileURL.deletingLastPathComponent() == directory,
              Self.extensions.contains(stagedURL.pathExtension.lowercased()),
              UUID(uuidString: stagedURL.deletingPathExtension().lastPathComponent) != nil else {
            throw GeneratedImageStagingError.unsafeFile
        }
        let values = try stagedURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw GeneratedImageStagingError.unsafeFile }
        try FileManager.default.removeItem(at: stagedURL)
    }

    private func validateDirectory() throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              directory.resolvingSymlinksInPath().standardizedFileURL == directory else {
            throw GeneratedImageStagingError.unavailableDirectory
        }
    }
}
