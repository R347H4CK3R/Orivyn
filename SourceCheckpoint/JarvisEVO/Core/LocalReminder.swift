import Foundation

/// A one-time local notification, not an autonomous model task. The OS pending
/// queue is its only persistent store; this value is a validated display snapshot.
struct LocalReminder: Identifiable, Equatable, Sendable {
    static let maximumCount = 48
    static let maximumTitleCharacters = 120
    static let maximumTitleBytes = 480
    static let maximumNotesBytes = 2_000
    static let maximumDelay: TimeInterval = 365 * 24 * 60 * 60
    static let identifierPrefix = "orivyn.reminder."

    let id: UUID
    let title: String
    let notes: String
    let date: Date
    var notificationIdentifier: String { Self.identifierPrefix + id.uuidString }

    static func validated(title: String, notes: String, date: Date, now: Date) throws -> LocalReminder {
        let title = try validatedTitle(title, notes: notes)
        let delay = date.timeIntervalSince(now)
        guard date.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
              delay >= 5, delay <= maximumDelay else { throw ReminderError.invalidDate }
        return LocalReminder(id: UUID(), title: title, notes: notes, date: date)
    }

    static func validatedTitle(_ title: String, notes: String) throws -> String {
        // Bound bytes before grapheme segmentation to avoid a huge combining-mark
        // sequence passing a character-only limit. Notes retain intentional spacing.
        guard notes.utf8.count <= maximumNotesBytes else { throw ReminderError.notesTooLong }
        guard title.utf8.count <= maximumTitleBytes, !title.contains("\0"), !notes.contains("\0") else {
            throw ReminderError.invalidText
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumTitleCharacters else { throw ReminderError.invalidTitle }
        return trimmed
    }
}

enum ReminderError: Error, LocalizedError, Equatable {
    case invalidTitle, invalidText, notesTooLong, invalidDate
    case permissionDenied, permissionUnavailable, capacityReached, systemCapacityReached
    case busy, notScheduled, notFound, cancellationFailed

    var errorDescription: String? {
        switch self {
        case .invalidTitle: "Enter a reminder title of 1–120 characters."
        case .invalidText: "Keep the title within 480 UTF-8 bytes and remove null characters from the title or notes."
        case .notesTooLong: "Keep reminder notes within 2,000 UTF-8 bytes."
        case .invalidDate: "Choose a date at least 5 seconds ahead and no more than 365 days away."
        case .permissionDenied: "Notifications are off for Orivyn. Enable them in iOS Settings before scheduling a reminder."
        case .permissionUnavailable: "iOS notification permission is unavailable. Check this app’s notification settings and try again."
        case .capacityReached: "Orivyn already has 48 pending reminders. Cancel one before adding another."
        case .systemCapacityReached: "This app’s iOS notification queue is full. Cancel an existing notification before adding another."
        case .busy: "Another reminder operation is still finishing. Please try again when it completes."
        case .notScheduled: "iOS did not retain this reminder in its pending queue. It has not been confirmed as scheduled. Try again."
        case .notFound: "This reminder is no longer pending. The list has been refreshed."
        case .cancellationFailed: "iOS still lists this reminder as pending. Its cancellation could not be confirmed. Please try again."
        }
    }
}
