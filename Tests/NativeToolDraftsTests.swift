import XCTest
@testable import JarvisEVO

/// These tests exercise the actual value validators. System-editor presentation,
/// cancellation and unchanged conversation drafts are covered by NativeToolsUITests.
final class NativeToolDraftsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000.375)

    func testMailValidationTrimsRecipientWithoutChangingSubjectOrBody() throws {
        let draft = try MailDraft.validated(recipient: "  person@example.com  ", subject: "  An idea  ", body: "First line\n\nSecond line + café\n")
        XCTAssertEqual(draft.recipient, "person@example.com")
        XCTAssertEqual(draft.subject, "  An idea  ")
        XCTAssertEqual(draft.body, "First line\n\nSecond line + café\n")
    }

    func testEmptyMailFieldsRemainAvailableForCompletionInSystemEditor() throws {
        let draft = try MailDraft.validated(recipient: "", subject: "", body: "")
        XCTAssertEqual(draft.recipient, "")
        XCTAssertEqual(draft.subject, "")
        XCTAssertEqual(draft.body, "")
    }

    func testMailRecipientLengthIsBoundedWithoutTruncation() throws {
        let recipient = String(repeating: "a", count: 308) + "@example.com"
        XCTAssertEqual(try MailDraft.validated(recipient: recipient, subject: "", body: "").recipient, recipient)
        XCTAssertThrowsError(try MailDraft.validated(recipient: "a" + recipient, subject: "", body: ""))
        XCTAssertThrowsError(try MailDraft.validated(recipient: String(repeating: "é", count: 161), subject: "", body: ""))
    }

    func testMailSubjectLimitUsesUTF8BytesWithoutTruncation() throws {
        let subject = String(repeating: "😀", count: 128)
        XCTAssertEqual(try MailDraft.validated(recipient: "", subject: subject, body: "").subject, subject)
        XCTAssertThrowsError(try MailDraft.validated(recipient: "", subject: subject + "a", body: ""))
    }

    func testMailBodyLimitUsesUTF8BytesWithoutTruncation() throws {
        let body = String(repeating: "😀", count: 8_192)
        XCTAssertEqual(try MailDraft.validated(recipient: "", subject: "", body: body).body, body)
        XCTAssertThrowsError(try MailDraft.validated(recipient: "", subject: "", body: body + "a"))
    }

    func testMailRejectsNullCharactersInEveryField() {
        XCTAssertThrowsError(try MailDraft.validated(recipient: "person\0@example.com", subject: "", body: ""))
        XCTAssertThrowsError(try MailDraft.validated(recipient: "", subject: "Hi\0there", body: ""))
        XCTAssertThrowsError(try MailDraft.validated(recipient: "", subject: "", body: "Hi\0there"))
    }

    func testMailRejectsRecipientNewlinesBeforeTrimming() {
        for recipient in ["person@example.com\n", "\rperson@example.com", "person@example.com\r\nBcc: other@example.com", "person@example.com\u{2028}other@example.com"] {
            XCTAssertThrowsError(try MailDraft.validated(recipient: recipient, subject: "", body: ""), recipient.debugDescription)
        }
    }

    func testCalendarValidationTrimsTitlePreservesNotesAndFractionalDates() throws {
        let draft = try CalendarDraft.validated(title: "  Read together \n", notes: "  Bring a book\n", start: start, end: Date(timeIntervalSince1970: 1_800_003_600.375))
        XCTAssertEqual(draft.title, "Read together")
        XCTAssertEqual(draft.notes, "  Bring a book\n")
        XCTAssertEqual(draft.start, Date(timeIntervalSince1970: 1_800_000_000.375))
        XCTAssertEqual(draft.end, Date(timeIntervalSince1970: 1_800_003_600.375))
    }

    func testCalendarRejectsBlankTitles() {
        for title in ["", " \n\t"] {
            XCTAssertThrowsError(try CalendarDraft.validated(title: title, notes: "", start: start, end: start.addingTimeInterval(60)))
        }
    }

    func testCalendarTitleAllows120EmojiButNot121Characters() throws {
        let title = String(repeating: "😀", count: 120)
        XCTAssertEqual(try CalendarDraft.validated(title: title, notes: "", start: start, end: start.addingTimeInterval(60)).title, title)
        XCTAssertThrowsError(try CalendarDraft.validated(title: String(repeating: "a", count: 121), notes: "", start: start, end: start.addingTimeInterval(60)))
        XCTAssertThrowsError(try CalendarDraft.validated(title: title + "a", notes: "", start: start, end: start.addingTimeInterval(60)))
    }

    func testCalendarTitleRejectsPathologicalSingleGraphemeAboveByteLimit() {
        let title = "a" + String(repeating: "\u{301}", count: 240)
        XCTAssertEqual(title.count, 1)
        XCTAssertThrowsError(try CalendarDraft.validated(title: title, notes: "", start: start, end: start.addingTimeInterval(60)))
    }

    func testCalendarNotesLimitUsesUTF8BytesWithoutTruncation() throws {
        let notes = String(repeating: "😀", count: 1_024)
        XCTAssertEqual(try CalendarDraft.validated(title: "Read", notes: notes, start: start, end: start.addingTimeInterval(60)).notes, notes)
        XCTAssertThrowsError(try CalendarDraft.validated(title: "Read", notes: notes + "a", start: start, end: start.addingTimeInterval(60)))
    }

    func testCalendarRejectsNullCharactersInTitleOrNotes() {
        XCTAssertThrowsError(try CalendarDraft.validated(title: "Read\0today", notes: "", start: start, end: start.addingTimeInterval(60)))
        XCTAssertThrowsError(try CalendarDraft.validated(title: "Read", notes: "Bring\0book", start: start, end: start.addingTimeInterval(60)))
    }

    func testCalendarEndMustFollowStartButPastDatesAreAllowedForExplicitReview() {
        XCTAssertThrowsError(try CalendarDraft.validated(title: "Read", notes: "", start: start, end: start))
        XCTAssertThrowsError(try CalendarDraft.validated(title: "Read", notes: "", start: start, end: start.addingTimeInterval(-1)))
        XCTAssertNoThrow(try CalendarDraft.validated(title: "Past event", notes: "", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60)))
    }

    func testCalendarSpanAllows366DaysButRejectsLonger() {
        XCTAssertNoThrow(try CalendarDraft.validated(title: "Read", notes: "", start: start, end: start.addingTimeInterval(31_622_400)))
        XCTAssertThrowsError(try CalendarDraft.validated(title: "Read", notes: "", start: start, end: start.addingTimeInterval(31_622_400.5)))
    }

    func testCalendarRejectsNonfiniteStartOrEnd() {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try CalendarDraft.validated(title: "Read", notes: "", start: Date(timeIntervalSince1970: value), end: start))
            XCTAssertThrowsError(try CalendarDraft.validated(title: "Read", notes: "", start: start, end: Date(timeIntervalSince1970: value)))
        }
    }

    func testBrowserPreservesExplicitHTTPSPathQueryAndFragment() throws {
        let destination = try BrowserDestination.validated("https://example.com/a%20page?x=one%2Btwo&y=2#section")
        XCTAssertEqual(destination.url.absoluteString, "https://example.com/a%20page?x=one%2Btwo&y=2#section")
        XCTAssertEqual(destination.url.host, "example.com")
        XCTAssertNoThrow(try BrowserDestination.validated("HTTPS://example.com:443/"))
    }

    func testBrowserRejectsNonHTTPSAndMissingHosts() {
        for address in ["", "example.com", "//example.com", "https://", "http://example.com", "javascript:alert(1)", "file:///tmp/private", "data:text/plain,hello", "orivyn://compose?text=hello"] {
            XCTAssertThrowsError(try BrowserDestination.validated(address), address)
        }
    }

    func testBrowserRejectsEmbeddedCredentialsIncludingEncodedUsernames() {
        for address in ["https://person@example.com/", "https://person:secret@example.com/", "https://%70erson@example.com/", "https://@example.com/", "https://:secret@example.com/"] {
            XCTAssertThrowsError(try BrowserDestination.validated(address), address)
        }
    }

    func testBrowserRejectsNonstandardOrInvalidPorts() {
        for address in ["https://example.com:80/", "https://example.com:8443/", "https://example.com:0/", "https://example.com:65536/", "https://example.com:abc/"] {
            XCTAssertThrowsError(try BrowserDestination.validated(address), address)
        }
    }

    func testBrowserRejectsRawWhitespaceAndControlCharactersInsteadOfRepairingThem() {
        for address in [" https://example.com", "https://example.com ", "https://example.com/a b", "https://example.com/\n", "https://example.com/\r", "https://example.com/\t", "https://example.com/\0", "https://example.com/\u{7F}", "https://example.com/\u{A0}"] {
            XCTAssertThrowsError(try BrowserDestination.validated(address), address.debugDescription)
        }
    }

    func testBrowserLimitUsesUTF8BytesWithoutTruncation() throws {
        let address = "https://example.com/" + String(repeating: "a", count: 4_076)
        XCTAssertEqual(try BrowserDestination.validated(address).url.absoluteString, address)
        XCTAssertThrowsError(try BrowserDestination.validated(address + "a"))
        XCTAssertThrowsError(try BrowserDestination.validated("https://example.com/" + String(repeating: "😀", count: 1_020)))
    }
}
