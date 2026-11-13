import Foundation
import CoreFoundation
import Observation
import UserNotifications

enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized, provisional, ephemeral, unavailable
    var permitsScheduling: Bool { self == .authorized || self == .provisional || self == .ephemeral }
}

struct ReminderNotificationQueue: Sendable {
    let reminders: [LocalReminder]
    /// Includes unrelated/malformed app notifications so creating a reminder cannot
    /// intentionally overflow iOS's 64-request queue and evict another feature.
    let totalPendingCount: Int
}

@MainActor
protocol ReminderNotifications: AnyObject {
    func authorizationStatus() async -> ReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func pending() async -> ReminderNotificationQueue
    func add(_ reminder: LocalReminder) async throws
    func removePending(identifier: String) async
}

@MainActor
final class SystemReminderNotifications: ReminderNotifications {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) { self.center = center }

    func authorizationStatus() async -> ReminderAuthorization {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let result: ReminderAuthorization
                switch settings.authorizationStatus {
                case .notDetermined: result = .notDetermined
                case .denied: result = .denied
                case .authorized: result = .authorized
                case .provisional: result = .provisional
                case .ephemeral: result = .ephemeral
                @unknown default: result = .unavailable
                }
                continuation.resume(returning: result)
            }
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    func pending() async -> ReminderNotificationQueue {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                let now = Date()
                let reminders = requests.compactMap { Self.reminder(from: $0, now: now) }
                continuation.resume(returning: ReminderNotificationQueue(reminders: reminders, totalPendingCount: requests.count))
            }
        }
    }

    func add(_ reminder: LocalReminder) async throws {
        let request = Self.request(for: reminder)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            center.add(request) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func removePending(identifier: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    nonisolated static func request(for reminder: LocalReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.notes
        content.sound = .default
        content.userInfo = ["owner": "orivyn.local-reminder", "version": 1,
                            "id": reminder.id.uuidString, "date": reminder.date.timeIntervalSince1970]
        return UNNotificationRequest(identifier: reminder.notificationIdentifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components(for: reminder.date), repeats: false))
    }

    nonisolated static func reminder(from request: UNNotificationRequest, now: Date) -> LocalReminder? {
        let info = request.content.userInfo
        guard info["owner"] as? String == "orivyn.local-reminder",
              let version = info["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let rawID = info["id"] as? String, let id = UUID(uuidString: rawID), rawID == id.uuidString,
              request.identifier == LocalReminder.identifierPrefix + id.uuidString,
              let timestamp = info["date"] as? NSNumber, CFGetTypeID(timestamp) != CFBooleanGetTypeID(),
              timestamp.doubleValue.isFinite,
              let title = try? LocalReminder.validatedTitle(request.content.title, notes: request.content.body),
              title == request.content.title,
              let trigger = request.trigger as? UNCalendarNotificationTrigger, !trigger.repeats else { return nil }
        let date = Date(timeIntervalSince1970: timestamp.doubleValue)
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0, remaining <= LocalReminder.maximumDelay else { return nil }
        let actual = trigger.dateComponents, expected = components(for: date)
        guard actual.calendar?.identifier == .gregorian,
              actual.timeZone?.secondsFromGMT(for: date) == 0,
              actual.year == expected.year, actual.month == expected.month, actual.day == expected.day,
              actual.hour == expected.hour, actual.minute == expected.minute, actual.second == expected.second,
              actual.era == nil || actual.era == 1,
              actual.nanosecond == nil || actual.nanosecond == 0,
              actual.weekday == nil, actual.weekdayOrdinal == nil, actual.weekOfYear == nil,
              actual.weekOfMonth == nil, actual.yearForWeekOfYear == nil, actual.quarter == nil,
              actual.isLeapMonth != true else { return nil }
        return LocalReminder(id: id, title: title, notes: request.content.body, date: date)
    }

    nonisolated private static func components(for date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // Newly validated reminders store their canonical whole-second fire date.
        // Round legacy fractional payloads upward too, never before their stored date.
        // Decoding checks this same precision rule instead of ignoring trigger fields.
        let wholeSecond = Date(timeIntervalSinceReferenceDate: ceil(date.timeIntervalSinceReferenceDate))
        var result = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: wholeSecond)
        result.calendar = calendar
        result.timeZone = calendar.timeZone
        return result
    }
}

@MainActor @Observable
final class ReminderScheduler {
    static let shared = ReminderScheduler(notifications: SystemReminderNotifications())
    private(set) var reminders: [LocalReminder] = []
    private(set) var authorization: ReminderAuthorization = .notDetermined
    private(set) var isBusy = false
    private let notifications: any ReminderNotifications
    private let now: () -> Date

    init(notifications: any ReminderNotifications, now: @escaping () -> Date = Date.init) {
        self.notifications = notifications
        self.now = now
    }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        authorization = await notifications.authorizationStatus()
        _ = await reconcile()
    }

    @discardableResult
    func create(title: String, notes: String, date: Date) async throws -> LocalReminder {
        guard !isBusy else { throw ReminderError.busy }
        _ = try LocalReminder.validated(title: title, notes: notes, date: date, now: now())
        isBusy = true
        defer { isBusy = false }
        do {
            try Task.checkCancellation()
            try checkCapacity(await reconcile())
            authorization = await notifications.authorizationStatus()
            if authorization == .notDetermined {
                let granted = try await notifications.requestAuthorization()
                authorization = await notifications.authorizationStatus()
                guard granted else { throw ReminderError.permissionDenied }
            }
            guard authorization.permitsScheduling else {
                throw authorization == .denied ? ReminderError.permissionDenied : ReminderError.permissionUnavailable
            }
            // Permission UI may take arbitrarily long, and other app features can change
            // the OS queue meanwhile. Neither the first date nor capacity check is final.
            try checkCapacity(await reconcile())
            try Task.checkCancellation()
            let reminder = try LocalReminder.validated(title: title, notes: notes, date: date, now: now())
            do { try await notifications.add(reminder) }
            catch {
                _ = await reconcile()
                // An interrupted OS callback can be ambiguous. Actual retention wins;
                // returning it prevents a retry from creating a second reminder.
                if let confirmed = reminders.first(where: { $0 == reminder }) { return confirmed }
                throw error
            }
            _ = await reconcile()
            guard let confirmed = reminders.first(where: { $0 == reminder }) else { throw ReminderError.notScheduled }
            return confirmed
        } catch {
            // A refusal, cancellation or failure can occur after an arbitrarily long
            // suspension. Do not leave a stale optimistic snapshot on the list.
            authorization = await notifications.authorizationStatus()
            _ = await reconcile()
            throw error
        }
    }

    func cancel(id: UUID) async throws {
        guard !isBusy else { throw ReminderError.busy }
        isBusy = true
        defer { isBusy = false }
        _ = await reconcile()
        try Task.checkCancellation()
        guard let reminder = reminders.first(where: { $0.id == id }) else { throw ReminderError.notFound }
        await notifications.removePending(identifier: reminder.notificationIdentifier)
        _ = await reconcile()
        guard !reminders.contains(where: { $0.id == id }) else { throw ReminderError.cancellationFailed }
    }

    private func reconcile() async -> ReminderNotificationQueue {
        let queue = await notifications.pending()
        reminders = queue.reminders.sorted {
            if $0.date == $1.date { return $0.id.uuidString < $1.id.uuidString }
            return $0.date < $1.date
        }
        return queue
    }

    private func checkCapacity(_ queue: ReminderNotificationQueue) throws {
        guard queue.reminders.count < LocalReminder.maximumCount else { throw ReminderError.capacityReached }
        guard queue.totalPendingCount < 64 else { throw ReminderError.systemCapacityReached }
    }
}
