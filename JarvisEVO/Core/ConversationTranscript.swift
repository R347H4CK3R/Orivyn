import Foundation

/// Text transcript only. Export is user initiated; attachments are named, never
/// embedded. Message bodies are preserved verbatim, including partial output.
enum ConversationTranscript {
    static func markdown(_ conversation: Conversation) -> String {
        "# \(metadata(conversation.title))\n\n" + conversation.messages.map { message in
            let role: String
            switch message.role {
            case .user: role = "You"
            case .assistant: role = "Jarvis"
            case .system: role = "System"
            }
            let state: String
            switch message.state {
            case .complete: state = ""
            case .streaming: state = " — Streaming — incomplete"
            case .interrupted: state = " — Interrupted — incomplete"
            case .failed: state = " — Failed — incomplete"
            }
            var section = "## \(role)\(state)\n\n\(message.content)"
            if !message.attachments.isEmpty {
                section += "\n\nAttachments (names only):\n"
                section += message.attachments.map { "- " + metadata($0.name) }.joined(separator: "\n")
                section += "\n\nAttachment contents and files are not included in this transcript."
            }
            return section
        }.joined(separator: "\n\n")
    }

    /// Only export metadata is escaped; never reinterpret or alter message text.
    private static func metadata(_ value: String) -> String {
        let singleLine = String(String.UnicodeScalarView(value.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? UnicodeScalar(32)! : $0
        }))
        return singleLine.reduce(into: "") { output, character in
            if "\\`*_{}[]()#+-!|><&".contains(character) { output += "\\" }
            output.append(character)
        }
    }
}
