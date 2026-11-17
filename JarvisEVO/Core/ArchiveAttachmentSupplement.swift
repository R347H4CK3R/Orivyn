import Foundation

/// A separately reviewed, immutable supplement. Source evidence does not grant
/// access to a file; the coordinator must verify/copy/import it before applying.
enum ArchiveAttachmentSupplement {
    enum Origin: String, Codable, Equatable, Sendable { case userReviewed, legacyMap }
    struct Source: Codable, Equatable, Sendable {
        var origin: Origin = .userReviewed
        var archiveSHA256: String
        var mapSHA256: String
        var conversationID: UUID
        var messageID: UUID
        var relativePath: String
        var bytes: UInt64
        var sha256: String
    }
    struct Receipt: Codable, Equatable, Sendable {
        let source: Source
        let epoch: UUID
        let attachment: ChatAttachment
    }
    enum Failure: LocalizedError {
        case invalid, changed, conflict, limit, unprovenImport
        var errorDescription: String? {
            switch self {
            case .invalid: "This attachment does not have a supported, verified restore binding."
            case .changed: "The reviewed message or history changed. Review this attachment again."
            case .conflict: "This attachment source or local identity already has a different binding."
            case .limit: "This attachment supplement exceeds a safe storage limit."
            case .unprovenImport: "This older restore preserved local conversations, so its receipt cannot prove which messages were imported. This file cannot be attached safely."
            }
        }
    }
    static func validate(_ source: Source) throws {
        func hash(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        let path = source.relativePath
        // Bound the input before split allocates one element per delimiter.
        guard !path.isEmpty, path.utf8.count <= 4096 else { throw Failure.invalid }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard hash(source.archiveSHA256), hash(source.mapSHA256), hash(source.sha256),
              source.bytes > 0, source.bytes <= 10 * 1024 * 1024,
              !path.contains("\\"), !path.contains(":"), !path.contains("%"),
              path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              components.count <= 64, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 })
        else { throw Failure.invalid }
    }
    /// Structural boundary only: local byte validation and image provenance are
    /// required from the trusted importer, never from export-provided metadata.
    static func validate(_ attachment: ChatAttachment, source: Source) throws {
        guard attachment.hasValidStorageBinding, attachment.byteCount > 0,
              UInt64(attachment.byteCount) == source.bytes,
              !attachment.name.isEmpty, attachment.name.utf8.count <= 1024,
              attachment.name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              (attachment.extractedText?.utf8.count ?? 0) <= 1_000_000 else { throw Failure.invalid }
        if attachment.isImage {
            guard ChatAttachment.imageFileExtension(for: attachment.mediaType) != nil else { throw Failure.invalid }
        } else {
            let suffix: String
            switch attachment.mediaType {
            case "text/plain": suffix = "txt"
            case "application/pdf": suffix = "pdf"
            default: throw Failure.invalid
            }
            guard attachment.relativePath == attachment.id.uuidString + "." + suffix,
                  attachment.previewRelativePath == nil else { throw Failure.invalid }
        }
    }

}
