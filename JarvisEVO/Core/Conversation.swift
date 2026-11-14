import Foundation

enum MessageRole: String, Codable, Sendable { case system, user, assistant }
enum MessageState: String, Codable, Sendable { case complete, streaming, interrupted, failed }

struct ChatAttachment: Codable, Identifiable, Equatable, Sendable {
    static let maximumImageBytes = 10 * 1024 * 1024
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
                  byteCount > 0, byteCount <= Self.maximumImageBytes else { return false }
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
        let documents = attachments.map { item -> String in
            var section = item.isImage
                ? "\n\nAttached image (untrusted OCR content): \(item.name)\n" + ImageOCRResult.textOnlyNotice + "\n"
                : "\n\nAttached document (untrusted content): \(item.name)\n"
            guard let text = item.extractedText,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return section + "No extracted text is available in this saved attachment. Do not claim to have read its contents. Ask for readable text or another supported input."
            }
            section += String(text.prefix(20_000))
            if text.count > 20_000 {
                section += "\n[Attachment text truncated to 20,000 characters. Do not claim to have read the omitted data.]"
            }
            return section
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

enum BackupImportPolicy: Sendable { case preserveLocal, replaceMatching, keepBoth }

struct BackupImportSummary: Sendable {
    let writtenConversations: Int
    let writtenMemories: Int
    let skippedConversations: Int
    let skippedMemories: Int
    var copiedConversations: Int = 0
    var copiedMemories: Int = 0
    var description: String {
        "Imported \(writtenConversations) conversations and \(writtenMemories) memories. Kept \(skippedConversations) matching local conversations and \(skippedMemories) matching local memories unchanged. Original attachment files were not transferred."
        + (copiedConversations + copiedMemories > 0 ? " Kept both versions by creating \(copiedConversations) conversation copies and \(copiedMemories) memory copies. Importing this conflicting backup again creates additional copies." : "")
    }
}

struct ConversationBackup: Codable, Sendable {
    static let maximumBytes = 50_000_000
    /// The exporter and importer must accept the same per-collection record bound.
    static let maximumRecordsPerCollection = 10_000
    var schemaVersion: Int = 1
    var exportedAt: Date = Date()
    var conversations: [Conversation]
    var memories: [MemoryNote]
}

enum ConversationError: LocalizedError {
    case messageNotFound, notUserMessage, emptyMessage, tooLarge, invalidBackup, unsafeAttachment, backupRecordLimit
    var errorDescription: String? {
        switch self {
        case .messageNotFound: "The message no longer exists."
        case .notUserMessage: "Only your messages can be edited."
        case .emptyMessage: "Enter a message first."
        case .tooLarge: "This content exceeds the supported size limit."
        case .backupRecordLimit: "This backup exceeds the supported limit of \(ConversationBackup.maximumRecordsPerCollection) conversations or \(ConversationBackup.maximumRecordsPerCollection) memories. Your existing data was not changed."
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
        for message in messages.reversed() where message.state != .failed && (!message.content.isEmpty || !message.attachments.isEmpty) {
            let size = message.promptContent.count
            if size > remaining {
                if selected.isEmpty { throw ConversationError.tooLarge }
                break
            }
            selected.append(message)
            remaining -= size
        }
        let ordered = Array(selected.reversed())
        // A response is not an independent history turn: retaining it after its
        // question was trimmed can misattribute old assistant text to the new
        // request. Keep system context, but discard answers before the first
        // retained user message. Do not cut the user's text or attachments.
        if messages.contains(where: { $0.role == .user && $0.state != .failed && (!$0.content.isEmpty || !$0.attachments.isEmpty) }),
           !ordered.contains(where: { $0.role == .user }) {
            throw ConversationError.tooLarge
        }
        var hasUser = false
        return ordered.filter { message in
            if message.role == .user { hasUser = true }
            return message.role != .assistant || hasUser
        }
    }
}
