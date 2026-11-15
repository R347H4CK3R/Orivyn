import Foundation

/// Reads only saved message text from the current in-memory history. No attachment
/// paths, original files, model inference, network or write capability is supplied.
enum LocalConversationRead {
    static func authorizedIDs(history: [LocalAgentSnapshot.Event]) -> Set<UUID> {
        var ids = Set<UUID>()
        for event in history where event.name == "search_conversations" && event.outcome == "succeeded" {
            guard let result = event.result, result.utf8.count <= 4096,
                  let data = result.data(using: .utf8),
                  let value = try? JSONDecoder().decode(MCPJSONValue.self, from: data),
                  let matches = value.objectValue?["matches"]?.arrayValue else { continue }
            for match in matches.prefix(10) {
                if let text = match.objectValue?["id"]?.stringValue, let id = UUID(uuidString: text) { ids.insert(id) }
            }
        }
        return ids
    }

    static func read(conversations: [Conversation], arguments: MCPJSONValue, authorizedIDs: Set<UUID>) throws -> MCPJSONValue {
        guard let args = arguments.objectValue, Set(args.keys) == Set(["id", "messageIndex", "offset"]),
              let idText = args["id"]?.stringValue, let id = UUID(uuidString: idText), authorizedIDs.contains(id),
              let index = args["messageIndex"]?.integerValue, (0...9999).contains(index),
              let offset = args["offset"]?.integerValue, (0...1_000_000).contains(offset),
              let conversation = conversations.first(where: { $0.id == id }),
              conversation.messages.indices.contains(Int(index)) else { throw LocalAgentError.invalidState }
        let message = conversation.messages[Int(index)]
        guard message.state != .streaming, message.content.utf8.count <= 1_000_000,
              offset <= message.content.utf8.count else { throw LocalAgentError.invalidState }
        // Offsets are UTF-8 scalar boundaries, never grapheme counts or lossy slices.
        let bytes = message.content.utf8
        let start = bytes.index(bytes.startIndex, offsetBy: Int(offset))
        guard let scalarStart = start.samePosition(in: message.content.unicodeScalars) else { throw LocalAgentError.invalidState }
        var text = "", count = 0
        for scalar in message.content.unicodeScalars[scalarStart...] {
            let part = String(scalar), size = part.utf8.count
            if count + size > 512 { break }
            text += part; count += size
        }
        let end = Int(offset) + count
        let moreText = end < bytes.count
        let next: MCPJSONValue
        if moreText { next = .object(["messageIndex": .integer(index), "offset": .integer(Int64(end))]) }
        else if Int(index) + 1 < conversation.messages.count && index < 9999 {
            next = .object(["messageIndex": .integer(index + 1), "offset": .integer(0)])
        } else { next = .null }
        return .object(["id": .string(id.uuidString), "messageID": .string(message.id.uuidString),
            "messageIndex": .integer(index), "role": .string(message.role.rawValue), "state": .string(message.state.rawValue),
            "offset": .integer(offset), "text": .string(text), "messageBytes": .integer(Int64(bytes.count)),
            "messageTruncated": .bool(moreText || offset > 0), "totalMessages": .integer(Int64(conversation.messages.count)),
            "messageWindowLimited": .bool(conversation.messages.count > 10_000), "next": next,
            "attachmentContentsIncluded": .bool(false), "omittedAttachments": .integer(Int64(message.attachments.count)),
            "evidenceSource": .string("saved_message_untrusted")])
    }
}
