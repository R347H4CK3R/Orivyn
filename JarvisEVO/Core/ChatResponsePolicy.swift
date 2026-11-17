import Foundation

/// Text assistance is not an execution permission or a claim that tools ran.
enum ChatResponsePolicy {
    static let instructions = """
    Jarvis, Orivyn's general-purpose assistant: write Python/code and useful text directly. Writing code as text is different from executing it; no runtime needed. Do not repeat or paraphrase the user's request as an opening. Do not invent tools or claim actions without recorded results.
    The three reads below run via bounded routing. Fresh local-model chat may choose these reads or calculate exact-request approximate arithmetic, not word problems or code, within three total calls. Automatic qualifies only after resolving a concrete local model. Attachments, external drafts, no-tools requests and remote providers exclude this loop. App-recorded receipts describe operations; model prose is not proof. No broader autonomy.
    With a connected catalog and concrete local model, fresh chat may propose one tool from its schemas locally, never execute it. Plugin calls require exact-call review by the user in Orivyn's review screen on a configured connection. Jarvis cannot run a plugin call without the user reviewing its exact name and arguments. No policy-compliance exception. Provider authentication is not your approval to execute. No autonomous arbitrary plugin/app installation. Inputs are text only: image OCR is not pixels; never infer unseen visuals.
    """ + "\n" + DirectChatRead.promptInventory
}

/// Separates a model's <think> channels from its visible answer before
/// display, persistence and speech. Delimiter buffers stay bounded; leading answer whitespace is held until classified.
/// GenerationRequest bounds overall output. No reasoning log.
/// Markdown code literals are preserved; unmarked prose tags are treated as channels.
struct ChatAnswerStream {
    private enum Phase { case prefix, reasoning, answer }
    private var phase: Phase = .prefix
    private var pending = ""
    private var whitespace = ""
    private var code = CodeLiteralState()
    // Do not trust an unmatched inline delimiter as proof that later text is code.
    // Hold its contents until a matching delimiter, or reparse on finalization.
    private var inlinePending = ""
    private var inlineStartCode: CodeLiteralState?
    private var reasoningDepth = 0
    private let opening = "<think>"
    private let closing = "</think>"

    mutating func append(_ piece: String) -> String {
        var visible = ""
        for character in piece {
            switch phase {
            case .answer:
                // Finish a Markdown delimiter run before deciding whether this is code.
                code.prepare(for: character)
                if code.inlineWidth == 0 && !inlinePending.isEmpty {
                    visible += inlinePending; inlinePending = ""; inlineStartCode = nil
                }
                if code.inlineWidth > 0 {
                    if inlineStartCode == nil {
                        inlineStartCode = code
                        inlineStartCode?.inlineWidth = 0
                        inlineStartCode?.run = nil
                        inlineStartCode?.runWidth = 0
                    }
                    inlinePending.append(character); code.record(character)
                    continue
                }
                if pending.isEmpty && code.isCode {
                    visible.append(character); code.record(character)
                    continue
                }
                pending.append(character)
                if pending == opening {
                    pending = ""; reasoningDepth = 1; phase = .reasoning
                } else {
                    while !pending.isEmpty && !opening.hasPrefix(pending) {
                        let literal = pending.removeFirst()
                        visible.append(literal); code.record(literal)
                    }
                }
            case .prefix:
                if pending.isEmpty && character.isWhitespace {
                    whitespace.append(character)
                    continue
                }
                pending.append(character)
                var prefixCode = code
                for character in whitespace { prefixCode.record(character) }
                let isIndentedCode = prefixCode.indentation >= 4
                if pending == opening && !isIndentedCode {
                    pending = ""; whitespace = ""; reasoningDepth = 1; phase = .reasoning
                } else if isIndentedCode || !opening.hasPrefix(pending) {
                    let literal = whitespace + pending
                    visible += literal
                    for character in literal { code.record(character) }
                    whitespace = ""; pending = ""; phase = .answer
                }
            case .reasoning:
                pending.append(character)
                if pending.hasSuffix(opening) {
                    pending = ""; reasoningDepth += 1
                } else if pending.hasSuffix(closing) {
                    pending = ""; reasoningDepth -= 1
                    if reasoningDepth == 0 { phase = .prefix }
                } else if pending.count > closing.count {
                    pending = String(pending.suffix(closing.count))
                }
            }
        }
        return visible
    }

    mutating func finish() -> String {
        // A confirmed but unclosed reasoning channel is never an answer.
        var suffix = phase == .reasoning ? "" : whitespace + pending
        pending = ""; whitespace = ""
        // A delimiter at EOF can complete a real inline code span.
        code.prepare(for: "\0")
        if !inlinePending.isEmpty {
            let deferred = inlinePending
            inlinePending = ""
            if code.inlineWidth == 0 {
                suffix += deferred
            } else {
                // The opening delimiter was already emitted. Without a match,
                // Markdown treats it literally; filter the rest as ordinary text.
                var fallback = ChatAnswerStream()
                fallback.phase = .answer
                fallback.code = inlineStartCode ?? CodeLiteralState()
                suffix += fallback.append(deferred) + fallback.finish()
            }
        }
        inlineStartCode = nil
        return suffix
    }

    /// Incremental Markdown delimiter recognition. Unresolved inline contents are
    /// held separately, within GenerationRequest's output bound. No reasoning log.
    private struct CodeLiteralState {
        var fence: Character?
        var fenceWidth = 0
        var inlineWidth = 0
        var run: Character?
        var runWidth = 0
        var runAtMargin = false
        var closingFence = false
        var indentation = 0
        var lineWhitespace = true
        var escapeNext = false

        var isCode: Bool { fence != nil || inlineWidth > 0 || indentation >= 4 }

        mutating func prepare(for character: Character) {
            guard let marker = run, marker != character else { return }
            if let fence {
                if marker == fence && runAtMargin && runWidth >= fenceWidth {
                    closingFence = true
                }
            } else if inlineWidth > 0 {
                if marker == "`" && runWidth == inlineWidth { inlineWidth = 0 }
            } else if runAtMargin && runWidth >= 3 {
                fence = marker; fenceWidth = runWidth
            } else if marker == "`" {
                inlineWidth = runWidth
            }
            run = nil; runWidth = 0
        }

        mutating func record(_ character: Character) {
            prepare(for: character)
            if character.isNewline {
                if closingFence { fence = nil; fenceWidth = 0 }
                closingFence = false
                indentation = 0; lineWhitespace = true; escapeNext = false
                return
            }
            if closingFence && !character.isWhitespace { closingFence = false }
            let escaped = escapeNext && fence == nil && inlineWidth == 0
            escapeNext = !escaped && character == "\\" && fence == nil && inlineWidth == 0
            if !escaped && (character == "`" || character == "~") {
                if run == character { runWidth += 1 }
                else {
                    run = character; runWidth = 1
                    runAtMargin = lineWhitespace && indentation < 4
                }
            }
            if lineWhitespace {
                if character == " " { indentation += 1 }
                else if character == "\t" { indentation += 4 }
                else { lineWhitespace = false }
            }
        }
    }
}
