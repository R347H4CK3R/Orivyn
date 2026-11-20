import Foundation
import Observation

/// Validated values only. Constructing one never sends mail, saves an event or visits a website.
struct MailDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let recipient: String
    let subject: String
    let body: String

    private init(recipient: String, subject: String, body: String) {
        id = UUID(); self.recipient = recipient; self.subject = subject; self.body = body
    }

    static func validated(recipient: String, subject: String, body: String) throws -> Self {
        guard recipient.utf8.count <= 320 else { throw NativeToolDraftError.mailRecipientTooLong }
        guard subject.utf8.count <= 512 else { throw NativeToolDraftError.mailSubjectTooLong }
        guard body.utf8.count <= 32_768 else { throw NativeToolDraftError.mailBodyTooLong }
        guard !recipient.contains("\0"), !subject.contains("\0"), !body.contains("\0") else {
            throw NativeToolDraftError.invalidText
        }
        guard recipient.rangeOfCharacter(from: .newlines) == nil else { throw NativeToolDraftError.recipientNewline }
        // Apple's editor validates recipient addresses and lets the user complete blank fields.
        return Self(recipient: recipient.trimmingCharacters(in: .whitespaces), subject: subject, body: body)
    }
}

struct CalendarDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let notes: String
    let start: Date
    let end: Date

    private init(title: String, notes: String, start: Date, end: Date) {
        id = UUID(); self.title = title; self.notes = notes; self.start = start; self.end = end
    }

    static func validated(title: String, notes: String, start: Date, end: Date) throws -> Self {
        guard title.utf8.count <= 480 else { throw NativeToolDraftError.calendarTitle }
        guard notes.utf8.count <= 4_096 else { throw NativeToolDraftError.calendarNotesTooLong }
        guard !title.contains("\0"), !notes.contains("\0") else { throw NativeToolDraftError.invalidText }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120 else { throw NativeToolDraftError.calendarTitle }
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              end > start, end.timeIntervalSince(start) <= 31_622_400 else { throw NativeToolDraftError.calendarDates }
        return Self(title: title, notes: notes, start: start, end: end)
    }
}

struct BrowserDestination: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL

    private init(url: URL) { id = UUID(); self.url = url }

    static func validated(_ address: String) throws -> Self {
        guard address.utf8.count <= 4_096 else { throw NativeToolDraftError.browserAddressTooLong }
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard address.rangeOfCharacter(from: forbidden) == nil,
              let url = URL(string: address, encodingInvalidCharacters: false),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              host.rangeOfCharacter(from: forbidden) == nil,
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443 else { throw NativeToolDraftError.browserAddress }
        guard url.absoluteString.utf8.count <= 4_096 else { throw NativeToolDraftError.browserAddressTooLong }
        return Self(url: url)
    }
}

enum NativeToolDraftError: LocalizedError, Equatable {
    case invalidText, recipientNewline, mailRecipientTooLong, mailSubjectTooLong, mailBodyTooLong
    case calendarTitle, calendarNotesTooLong, calendarDates, browserAddress, browserAddressTooLong

    var errorDescription: String? {
        switch self {
        case .invalidText: "Remove null characters from the draft. Nothing has been sent or saved."
        case .recipientNewline: "Enter the recipient on one line. Add or change recipients in Apple's Mail editor."
        case .mailRecipientTooLong: "Keep the recipient within 320 UTF-8 bytes. Your text has not been shortened."
        case .mailSubjectTooLong: "Keep the subject within 512 UTF-8 bytes. Your text has not been shortened."
        case .mailBodyTooLong: "Keep the message within 32,768 UTF-8 bytes. Your text has not been shortened."
        case .calendarTitle: "Enter a title of 1–120 characters and at most 480 UTF-8 bytes."
        case .calendarNotesTooLong: "Keep event notes within 4,096 UTF-8 bytes. Your text has not been shortened."
        case .calendarDates: "Choose valid dates with the end after the start, no more than 366 days apart."
        case .browserAddress: "Enter a complete HTTPS address with a host, no username, password, spaces or control characters, and no port other than 443. Encode spaces in paths as %20."
        case .browserAddressTooLong: "Keep the full encoded address within 4,096 UTF-8 bytes. It has not been shortened."
        }
    }
}


/// Pure URL construction. No request is performed until the explicit Safari action.
enum WebSearchDestination {
    static func validated(_ terms: String) throws -> BrowserDestination {
        guard terms.utf8.count <= 1024,
              terms.rangeOfCharacter(from: CharacterSet.controlCharacters.union(.newlines)) == nil else { throw WebInputError.search }
        let query = terms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw WebInputError.search }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "duckduckgo.com"
        parts.path = "/"
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        // Form-style search servers may decode a literal + as a space.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url else { throw WebInputError.search }
        return try BrowserDestination.validated(url.absoluteString)
    }
}

struct WebNavigationDraft {
    let destination: BrowserDestination
    let isWebsite: Bool
    var actionTitle: String { isWebsite ? "Open website" : "Search DuckDuckGo" }

    static func validated(_ text: String) throws -> Self {
        guard text.utf8.count <= 4096 else { throw NativeToolDraftError.browserAddressTooLong }
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Classify trimmed input so leading whitespace cannot send a URL/token to search.
        // Scheme-like input must pass website validation, never silently become a search.
        if input.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil {
            return Self(destination: try BrowserDestination.validated(input), isWebsite: true)
        }
        return Self(destination: try WebSearchDestination.validated(input), isWebsite: false)
    }
}

@MainActor @Observable
final class WebBookmarkStore {
    private(set) var bookmarks: [String]
    private let defaults: UserDefaults
    private static let key = "orivyn.web.explicitBookmarks.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var seen = Set<String>()
        bookmarks = (defaults.stringArray(forKey: Self.key) ?? []).compactMap { value in
            guard let checked = try? Self.bookmarkAddress(value), seen.insert(checked).inserted else { return nil }
            return checked
        }
    }

    static func bookmarkAddress(_ text: String) throws -> String {
        let destination = try BrowserDestination.validated(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard var parts = URLComponents(url: destination.url, resolvingAgainstBaseURL: false) else { throw WebInputError.search }
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { throw WebInputError.search }
        return try BrowserDestination.validated(url.absoluteString).url.absoluteString
    }

    /// Only called after the user taps Save bookmark. Never an automatic visit history.
    func saveWebsite(_ text: String) throws {
        let address = try Self.bookmarkAddress(text)
        guard !bookmarks.contains(address) else { return }
        bookmarks.append(address)
        defaults.set(bookmarks, forKey: Self.key)
    }

    func remove(_ address: String) {
        bookmarks.removeAll { $0 == address }
        defaults.set(bookmarks, forKey: Self.key)
    }
}

enum WebInputError: LocalizedError {
    case search
    var errorDescription: String? { "Enter search words on one line, within 1,024 UTF-8 bytes. Nothing has been sent or shortened." }
}


/// Immutable per-presentation choice. Search and ordinary navigation default to normal Safari.
struct BrowserPresentation: Identifiable {
    let destination: BrowserDestination
    let prefersReader: Bool
    var id: UUID { destination.id }

    static func validated(_ text: String, reader: Bool = false) throws -> Self {
        let draft = try WebNavigationDraft.validated(text)
        guard !reader || draft.isWebsite else { throw NativeToolDraftError.browserAddress }
        return Self(destination: draft.destination, prefersReader: reader)
    }
}

/// Removes only named tracking query fields. All other URL bytes remain as entered.
/// This is not a privacy sanitizer: functional parameters, tokens and fragments may remain.
enum WebCleanLink {
    private static let trackingKeys: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "utm_source_platform", "utm_creative_format", "utm_marketing_tactic",
        "gclid", "dclid", "fbclid", "msclkid", "mc_cid", "mc_eid"
    ]

    static func validated(_ text: String) throws -> String {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try BrowserDestination.validated(original)
        let fragmentStart = original.firstIndex(of: "#") ?? original.endIndex
        let beforeFragment = original[..<fragmentStart]
        guard let queryStart = beforeFragment.firstIndex(of: "?") else { return original }
        let fields = beforeFragment[beforeFragment.index(after: queryStart)...]
            .split(separator: "&", omittingEmptySubsequences: false)
        let kept = fields.filter { field in
            let rawKey = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            guard let key = String(rawKey).removingPercentEncoding else { return true }
            return !trackingKeys.contains(key.lowercased())
        }
        if kept.count == fields.count { return original }
        let query = kept.isEmpty ? "" : "?" + kept.joined(separator: "&")
        let cleaned = String(original[..<queryStart]) + query + String(original[fragmentStart...])
        _ = try BrowserDestination.validated(cleaned)
        return cleaned
    }
}
