import Foundation
import Observation

/// Untrusted text only. Incoming links and shortcuts never execute or submit it.
struct IncomingTextRequest: Identifiable, Equatable, Sendable {
    static let textByteLimit = 8_192
    static let draftByteLimit = 32_768
    let id: UUID
    let text: String

    init(text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.contains("\0") else { throw IncomingTextError.invalidText }
        guard text.utf8.count <= Self.textByteLimit else { throw IncomingTextError.textTooLarge }
        id = UUID()
        self.text = text
    }

    static func parse(_ url: URL) throws -> Self {
        guard url.absoluteString.utf8.count <= 32_768,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "orivyn", parts.host?.lowercased() == "compose",
              parts.path.isEmpty, parts.user == nil, parts.password == nil,
              parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1,
              items[0].name == "text", let text = items[0].value else { throw IncomingTextError.invalidURL }
        // URLComponents decodes once and preserves literal '+' rather than form-decoding it.
        return try Self(text: text)
    }

    static func appending(_ text: String, to draft: String) throws -> String {
        _ = try Self(text: text)
        let separator = draft.isEmpty ? "" : "\n\n"
        guard draft.utf8.count <= draftByteLimit,
              draft.utf8.count + separator.utf8.count + text.utf8.count <= draftByteLimit else {
            throw IncomingTextError.draftTooLarge
        }
        return draft + separator + text
    }
}

enum IncomingTextError: LocalizedError, Equatable {
    case invalidURL, invalidText, textTooLarge, draftTooLarge, pendingRequest, composerBusy, staleRequest
    var errorDescription: String? {
        switch self {
        case .invalidURL: "This link is not a supported Orivyn text-sharing link. Nothing was sent."
        case .invalidText: "Add some text without null characters before continuing."
        case .textTooLarge: "Incoming text is limited to 8,192 UTF-8 bytes. Shorten it and try again."
        case .draftTooLarge: "Adding this text would exceed the 32,768-byte draft limit. Your existing draft is unchanged."
        case .pendingRequest: "Text is already waiting for review. Review or discard it before sharing more."
        case .composerBusy: "Finish the current response, voice session or import before adding text. Your draft is unchanged."
        case .staleRequest: "This request is no longer pending. Nothing was added."
        }
    }
}

/// In-process, foreground-only staging. Never stores shared text to disk or logs it.
@MainActor @Observable
final class IncomingTextInbox {
    static let shared = IncomingTextInbox()
    private(set) var pending: IncomingTextRequest?
    private(set) var lastError: String?

    @discardableResult func enqueue(_ text: String) throws -> IncomingTextRequest {
        guard pending == nil else { throw IncomingTextError.pendingRequest }
        let request = try IncomingTextRequest(text: text)
        pending = request
        lastError = nil
        return request
    }

    func receive(_ url: URL) {
        do { _ = try enqueue(IncomingTextRequest.parse(url).text) }
        catch { lastError = error.localizedDescription }
    }

    func discard(id: UUID) {
        guard pending?.id == id else { return }
        pending = nil
        lastError = nil
    }
    func dismissError() { lastError = nil }
}
