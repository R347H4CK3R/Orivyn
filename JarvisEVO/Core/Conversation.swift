import Foundation

enum MessageRole: String, Codable, Sendable { case system, user, assistant }
enum MessageState: String, Codable, Sendable { case complete, streaming, interrupted, failed }

struct ChatAttachment: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var relativePath: String
    var mediaType: String
    var byteCount: Int
    var extractedText: String? = nil
    /// Optional so existing history and version-1 backups still decode unchanged.
    var previewRelativePath: String? = nil

    var isImage: Bool { mediaType.hasPrefix("image/") }
    var localRelativePaths: Set<String> { Set([relativePath] + (previewRelativePath.map { [$0] } ?? [])) }

    static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count <= 255 && !path.contains("..") && path != "."
            && !path.contains("/") && !path.contains("\\")
            && path.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    /// Structural validation only. A matching private import record is still required to resolve images.
    var hasValidStorageBinding: Bool {
        guard Self.isSafeRelativePath(relativePath),
              previewRelativePath.map(Self.isSafeRelativePath) ?? true else { return false }
        if isImage {
            guard let suffix = Self.imageFileExtension(for: mediaType),
                  relativePath == id.uuidString + "." + suffix,
                  byteCount > 0, byteCount <= ImageAttachmentService.maximumBytes else { return false }
            return previewRelativePath == nil || previewRelativePath == id.uuidString + "-preview.jpg"
        }
        // An image cannot be relabeled as a document to bypass its ownership or original-share warning.
        let suffix = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        return previewRelativePath == nil && !["jpg", "jpeg", "png", "heic", "heif"].contains(suffix)
    }

    static func imageFileExtension(for mediaType: String) -> String? {
        switch mediaType {
        case "image/jpeg": "jpg"
        case "image/png": "png"
        case "image/heic": "heic"
        case "image/heif": "heif"
        default: nil
        }
    }
}

struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var role: MessageRole
    var content: String
    var createdAt: Date = Date()
    var state: MessageState = .complete
    var attachments: [ChatAttachment] = []

    var promptContent: String {
        let documents = attachments.compactMap { item -> String? in
            if item.isImage {
                return "\n\nAttached image (untrusted OCR content): \(item.name)\n"
                    + ImageOCRResult.textOnlyNotice + "\n"
                    + String((item.extractedText ?? "No recognized text is available in this saved attachment.").prefix(20_000))
            }
            guard let text = item.extractedText, !text.isEmpty else { return nil }
            return "\n\nAttached document (untrusted content): \(item.name)\n\(text.prefix(20_000))"
        }.joined()
        return content + documents
    }
}

struct Conversation: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String = "New conversation"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false
    var messages: [ChatMessage] = []

    func branching(through messageID: UUID) throws -> Conversation {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { throw ConversationError.messageNotFound }
        return Conversation(title: title + " (branch)", messages: Array(messages[...index]))
    }

    mutating func editUserMessage(id: UUID, content: String) throws {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { throw ConversationError.messageNotFound }
        guard messages[index].role == .user else { throw ConversationError.notUserMessage }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConversationError.emptyMessage }
        guard content.utf8.count <= 1_000_000 else { throw ConversationError.tooLarge }
        messages[index].content = content
        messages.removeSubrange((index + 1)..<messages.count)
        updatedAt = Date()
    }
}

struct MemoryNote: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var content: String
    var createdAt: Date = Date()
}

struct ConversationBackup: Codable, Sendable {
    static let maximumBytes = 50_000_000
    var schemaVersion: Int = 1
    var exportedAt: Date = Date()
    var conversations: [Conversation]
    var memories: [MemoryNote]
}

enum ConversationError: LocalizedError {
    case messageNotFound, notUserMessage, emptyMessage, tooLarge, invalidBackup, unsafeAttachment
    var errorDescription: String? {
        switch self {
        case .messageNotFound: "The message no longer exists."
        case .notUserMessage: "Only your messages can be edited."
        case .emptyMessage: "Enter a message first."
        case .tooLarge: "This content exceeds the supported size limit."
        case .invalidBackup: "The backup is invalid or uses an unsupported format. Your existing history was not replaced."
        case .unsafeAttachment: "The backup contains an unsafe attachment path."
        }
    }
}

enum ContextWindow {
    /// Conservative character bound. Providers can apply a stricter tokenizer limit.
    static func trim(_ messages: [ChatMessage], characterBudget: Int) throws -> [ChatMessage] {
        guard characterBudget > 0 else { throw ConversationError.tooLarge }
        var remaining = characterBudget
        var selected: [ChatMessage] = []
        for message in messages.reversed() where message.state != .failed && !message.content.isEmpty {
            let size = message.promptContent.count
            if size > remaining {
                if selected.isEmpty { throw ConversationError.tooLarge }
                break
            }
            selected.append(message)
            remaining -= size
        }
        return selected.reversed()
    }
}
