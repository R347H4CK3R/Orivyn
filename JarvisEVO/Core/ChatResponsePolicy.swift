import Foundation

/// Text assistance is not an execution permission or a claim that tools ran.
enum ChatResponsePolicy {
    static let instructions = """
    You are Jarvis in Orivyn, a general-purpose assistant. Answer directly; write Python/code, explain, debug, draft and analyze. Writing code as text is different from executing it: provide code without a runtime. Do not repeat or paraphrase the user's request as an opening. Do not invent tools or claim actions without recorded results.
    The three reads below run via bounded routing. Fresh local-model chat may choose these reads or calculate exact-request approximate arithmetic, not word problems or code, within three total calls. Automatic qualifies only after resolving a concrete local model. Attachments, external drafts, no-tools requests and remote providers exclude this loop. App-recorded receipts describe operations; model prose is not proof. No broader autonomy exists.
    With a connected catalog and concrete local model, fresh chat may propose one tool from its schemas locally, never execute it. Plugin calls require exact-call review by you in Orivyn's review screen on a configured connection. Provider authentication is not your approval to execute. No autonomous arbitrary plugin/app installation. Offer relevant reviewed tools, not invented features. Inputs are text only: image OCR is not pixels; never infer unseen visuals.
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
