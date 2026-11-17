import Foundation
import CoreFoundation

/// Converts one bounded export record to ordinary app history, never executable
/// instructions. The caller must retain the complete original archive separately.
/// This does not extract ZIPs, write history, or resolve attachment ownership.
enum ChatGPTConversationRestore {
    enum Failure: Error { case invalidRecord, invalidTree, missingIdentity, invalidTimestamp, limit }
    struct UnresolvedContent: Sendable {
        let messageID: UUID
        let source: String
        let originalJSON: Data
    }
    struct Result: Sendable {
        var unresolvedContent: [UnresolvedContent] = []
        var conversation: Conversation?
        /// All mapping nodes not activated as visible messages, including sibling branches.
        var omittedMessages: Int
    }

    /// Non-UUID export IDs require a persisted, archive-scoped identity map supplied
    /// by the coordinator. Never mint random IDs here: retries must deduplicate.
    static func convert(_ data: Data, identities: [String: UUID]) throws -> Result {
        try Task.checkCancellation()
        guard data.count <= 16_000_000 else { throw Failure.limit }
        return try convert(projected: ChatGPTRecordProjection.project(data), identities: identities)
    }
    static func convert(projected record: [String: Any], identities: [String: UUID]) throws -> Result {
        try Task.checkCancellation()
        guard let mapping = record["mapping"] as? [String: [String: Any]] else { throw Failure.invalidRecord }
        guard mapping.count <= 20_000 else { throw Failure.limit }
        if excluded(record) { return Result(conversation: nil, omittedMessages: mapping.count) }
        guard let externalID = record["id"] as? String, !externalID.isEmpty,
              let current = record["current_node"] as? String, !current.isEmpty else { throw Failure.invalidRecord }
        let id = try identity(externalID, key: "conversation:" + externalID, map: identities)
        let created = try timestamp(record["create_time"])
        let updated = try timestamp(record["update_time"])
        var branch: [[String: Any]] = [], visited = Set<String>(), cursor: String? = current
        while let key = cursor {
            try Task.checkCancellation()
            guard visited.insert(key).inserted, let node = mapping[key] else { throw Failure.invalidTree }
            branch.append(node)
            if node["parent"] is NSNull { cursor = nil }
            else if let parent = node["parent"] as? String, !parent.isEmpty { cursor = parent }
            else { throw Failure.invalidTree }
        }
        var messages: [ChatMessage] = [], messageIDs = Set<UUID>()
        var unresolved: [UnresolvedContent] = []
        for node in branch.reversed() {
            try Task.checkCancellation()
            guard let message = node["message"] as? [String: Any], !excluded(message),
                  let author = message["author"] as? [String: Any],
                  let roleName = author["role"] as? String,
                  let role = MessageRole(rawValue: roleName), role != .system else { continue }
            let metadata = message["metadata"] as? [String: Any]
            guard metadata?["is_visually_hidden_from_conversation"] as? Bool != true,
                  metadata?["is_user_system_message"] as? Bool != true else { continue }
            if role == .assistant {
                // JSON null is an unset optional routing field, not an internal channel.
                // Non-null unknown/malformed routing still fails closed.
                guard message["channel"] == nil || message["channel"] is NSNull || message["channel"] as? String == "final",
                      message["recipient"] == nil || message["recipient"] is NSNull || message["recipient"] as? String == "all" else { continue }
            }
            guard let content = message["content"] as? [String: Any],
                  let type = content["content_type"] as? String else { continue }
            let parts: [Any]
            if type == "text" || type == "multimodal_text" {
                guard let supplied = content["parts"] as? [Any] else { continue }
                parts = supplied
            } else if type == "code" {
                // Explicit visible code is inert history text, never a tool invocation.
                // Do not infer missing text from unknown fields or alternate parts.
                guard let supplied = content["text"] as? String else { continue }
                parts = [supplied]
            } else { continue }
            guard parts.count <= 20_000 else { throw Failure.limit }
            let text = parts.compactMap { $0 as? String }.joined(separator: "\n")
            let hasUnresolved = parts.contains { !($0 is String) } || !(metadata?["attachments"] as? [Any] ?? []).isEmpty
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasUnresolved else { continue }
            guard text.utf8.count <= 1_000_000 else { throw Failure.limit }
            guard let externalMessage = message["id"] as? String, !externalMessage.isEmpty else { throw Failure.invalidRecord }
            let messageID = try identity(externalMessage, key: legacyMessageKey(conversationID: externalID, messageID: externalMessage), map: identities)
            guard messageIDs.insert(messageID).inserted else { throw Failure.invalidRecord }
            let attachments = metadata?["attachments"] as? [Any] ?? []
            guard attachments.count <= 2048 else { throw Failure.limit }
            let opaqueCount = parts.reduce(0) { $0 + ($1 is String ? 0 : 1) }
            guard unresolved.count + opaqueCount + attachments.count <= 2048 else { throw Failure.limit }
            for part in parts where !(part is String) {
                try Task.checkCancellation()
                unresolved.append(UnresolvedContent(messageID: messageID, source: "contentPart",
                    originalJSON: try JSONSerialization.data(withJSONObject: part, options: [.fragmentsAllowed, .sortedKeys])))
            }
            if !attachments.isEmpty {
                for attachment in attachments {
                    try Task.checkCancellation()
                    unresolved.append(UnresolvedContent(messageID: messageID, source: "attachmentMetadata",
                        originalJSON: try JSONSerialization.data(withJSONObject: attachment, options: [.fragmentsAllowed, .sortedKeys])))
                }
            }
            messages.append(ChatMessage(id: messageID, role: role, content: text,
                createdAt: try timestamp(message["create_time"]), state: restoredState(message)))
        }
        let conversation = Conversation(id: id, title: String((record["title"] as? String ?? "Imported conversation").prefix(200)),
            createdAt: created, updatedAt: updated, isArchived: record["is_archived"] as? Bool ?? false, messages: messages)
        return Result(unresolvedContent: unresolved, conversation: conversation, omittedMessages: mapping.count - messages.count)
    }
    private static func restoredState(_ message: [String: Any]) -> MessageState {
        let status = message["status"] as? String
        if status == "finished_successfully" { return .complete }
        if status == "failed" || status == "error" { return .failed }
        let author = message["author"] as? [String: Any]
        if status == nil && author?["role"] as? String == "user" { return .complete }
        return .interrupted
    }
    private static func excluded(_ record: [String: Any]) -> Bool {
        let metadata = record["metadata"] as? [String: Any]
        return record["is_do_not_remember"] as? Bool == true || metadata?["is_do_not_remember"] as? Bool == true
    }
    /// Versioned byte-length framing prevents ("a:b", "c") from aliasing ("a", "b:c").
    /// The coordinator must persist this exact key with its chosen UUID before commit.
    static func legacyMessageKey(conversationID: String, messageID: String) -> String {
        "message:v1:\(conversationID.utf8.count):\(conversationID):\(messageID.utf8.count):\(messageID)"
    }
    private static func identity(_ source: String, key: String, map: [String: UUID]) throws -> UUID {
        if let id = UUID(uuidString: source) { return id }
        guard let id = map[key] else { throw Failure.missingIdentity }
        return id
    }
    private static func timestamp(_ value: Any?) throws -> Date {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, (-62_135_596_800...253_402_300_799).contains(number.doubleValue) else { throw Failure.invalidTimestamp }
        return Date(timeIntervalSince1970: number.doubleValue)
    }
}
