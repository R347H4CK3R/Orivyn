import XCTest
@testable import JarvisEVO

final class LocalReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testValidationTrimsTitleButPreservesNotes() throws {
        let reminder = try LocalReminder.validated(title: "  Call home \n", notes: "  Keep these notes.\n", date: now.addingTimeInterval(60), now: now)
        XCTAssertEqual(reminder.title, "Call home")
        XCTAssertEqual(reminder.notes, "  Keep these notes.\n")
        XCTAssertEqual(reminder.date, Date(timeIntervalSince1970: 1_800_000_060))
    }

    func testValidationRejectsEmptyAndOversizedTitles() {
        for title in ["", " \n\t", String(repeating: "a", count: 121)] {
            XCTAssertThrowsError(try LocalReminder.validated(title: title, notes: "", date: now.addingTimeInterval(60), now: now))
        }
        XCTAssertNoThrow(try LocalReminder.validated(title: String(repeating: "😀", count: 120), notes: "", date: now.addingTimeInterval(60), now: now))
    }

    func testNotesLimitUsesUTF8BytesNotCharacters() {
        XCTAssertNoThrow(try LocalReminder.validated(title: "Read", notes: String(repeating: "😀", count: 500), date: now.addingTimeInterval(60), now: now))
        XCTAssertThrowsError(try LocalReminder.validated(title: "Read", notes: String(repeating: "😀", count: 501), date: now.addingTimeInterval(60), now: now))
    }

    func testPathologicalSingleGraphemeTitleStillHasByteLimit() {
        let title = "a" + String(repeating: "\u{301}", count: 240)
        XCTAssertEqual(title.count, 1)
        XCTAssertEqual(title.utf8.count, 481)
        XCTAssertThrowsError(try LocalReminder.validated(title: title, notes: "", date: now.addingTimeInterval(60), now: now))
    }

    func testNullCharactersCannotSilentlyTruncateNotificationText() {
        XCTAssertThrowsError(try LocalReminder.validated(title: "Read\0later", notes: "", date: now.addingTimeInterval(60), now: now))
        XCTAssertThrowsError(try LocalReminder.validated(title: "Read", notes: "Chapter\0three", date: now.addingTimeInterval(60), now: now))
    }

    func testDateValidationIncludesFiveSecondsAnd365DaysBoundaries() {
        for seconds in [5.0, 31_536_000.0] {
            XCTAssertNoThrow(try LocalReminder.validated(title: "Read", notes: "", date: now.addingTimeInterval(seconds), now: now))
        }
        for seconds in [-1.0, 0.0, 4.99, 31_536_001.0, Double.infinity, Double.nan] {
            XCTAssertThrowsError(try LocalReminder.validated(title: "Read", notes: "", date: now.addingTimeInterval(seconds), now: now))
        }
    }

}
