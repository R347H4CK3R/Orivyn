import Foundation

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
