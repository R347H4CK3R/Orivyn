import Foundation

/// Text assistance is not an execution permission or a claim that tools ran.
enum ChatResponsePolicy {
    static let instructions = """
    You are Jarvis in Orivyn, a general-purpose conversational assistant, not just app help. Answer directly and do the useful part first. You can write Python and other code, explain, debug, draft and analyze text. Writing code as text is different from executing it; provide requested code even without a runtime. Do not repeat or paraphrase the user's request as an opening. Give the result, with brief relevant explanation. Do not invent tools or claim execution, browsing, installation or completed actions without a recorded result. The direct-read inventory below is exhaustive. Direct requests and supported natural questions about installed models, bundled app capabilities or saved memories run only those reads. Supported compound requests run up to three distinct local reads. Recognized direct requests use bounded language routing. Other fresh normal chat with a selected installed on-device model may choose these same three local reads when useful, including relevant saved-memory search, or answer without tools. This bounded loop has at most three reads; actual read receipts appear in chat and final model prose is not execution proof. Attachments, external result drafts, explicit no-tools requests, and remote providers do not use this loop. Automatic mode may use it after its existing preparation resolves a concrete local model. No broader autonomous tool execution exists. Plugin calls require exact-call review by you in Orivyn's review screen, using an already configured connection. Provider authentication is not your approval to execute; you cannot autonomously install arbitrary plugins or apps. If needed, offer the relevant reviewed tool screen, not unrelated app features. All providers receive text only; image attachments supply OCR, not image pixels. Do not infer unseen visual details.
    """ + "\n" + DirectChatRead.promptInventory
}

/// Separates a model's leading <think> channel from its visible answer before
/// display, persistence and speech. Delimiter buffers stay bounded; leading answer whitespace is held until classified.
/// GenerationRequest bounds overall output. No reasoning log.
/// Once answer text begins, literal tags (including in code) are preserved.
struct ChatAnswerStream {
    private enum Phase { case prefix, reasoning, answer }
    private var phase: Phase = .prefix
    private var pending = ""
    private var whitespace = ""
    private let opening = "<think>"
    private let closing = "</think>"

    mutating func append(_ piece: String) -> String {
        var visible = ""
        for character in piece {
            switch phase {
            case .answer:
                visible.append(character)
            case .prefix:
                if pending.isEmpty && character.isWhitespace {
                    whitespace.append(character)
                    continue
                }
                pending.append(character)
                if pending == opening {
                    pending = ""; whitespace = ""; phase = .reasoning
                } else if !opening.hasPrefix(pending) {
                    visible += whitespace + pending; whitespace = ""; pending = ""; phase = .answer
                }
            case .reasoning:
                pending.append(character)
                if pending.hasSuffix(closing) {
                    pending = ""; phase = .prefix
                } else if pending.count > closing.count {
                    pending = String(pending.suffix(closing.count))
                }
            }
        }
        return visible
    }

    mutating func finish() -> String {
        // A confirmed but unclosed reasoning channel is never an answer.
        let suffix = phase == .prefix ? whitespace + pending : ""
        pending = ""; whitespace = ""
        return suffix
    }
}
