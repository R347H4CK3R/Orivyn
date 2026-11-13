import Foundation
import Glibc

// Explicit OS boundary double; this is NOT UserNotifications or delivery proof.
@MainActor final class SystemReminderNotifications: ReminderNotifications {
    var status: ReminderAuthorization = .authorized
    var queue: [LocalReminder] = []
    var unrelated = 0, adds = 0
    var retainAdd = true, throwAfterAdd = false, refuseRemove = false
    var roundtripUnixDate = false
    var grant = true
    var permissionAction: (() -> Void)?
    var permissionWait: CheckedContinuation<Void, Never>?
    var holdPermission = false
    func authorizationStatus() async -> ReminderAuthorization { status }
    func requestAuthorization() async throws -> Bool {
        if holdPermission { await withCheckedContinuation { permissionWait = $0 } }
        permissionAction?(); status = grant ? .authorized : .denied; return grant
    }
    func pending() async -> ReminderNotificationQueue { .init(reminders: queue, totalPendingCount: queue.count + unrelated) }
    func add(_ reminder: LocalReminder) async throws {
        adds += 1
        if retainAdd {
            queue.append(roundtripUnixDate ? LocalReminder(id: reminder.id, title: reminder.title, notes: reminder.notes, date: Date(timeIntervalSince1970: reminder.date.timeIntervalSince1970)) : reminder)
        }
        if throwAfterAdd { throw CancellationError() }
    }
    func removePending(identifier: String) async {
        if !refuseRemove { queue.removeAll { $0.notificationIdentifier == identifier } }
    }
}
@main struct ReminderSmoke {
    @MainActor static func main() async throws {
        var checks: [[String: Any]] = []
        func record(_ label: String, _ passed: Bool) { checks.append(["check":label,"passed":passed]) }
        let base = Date(timeIntervalSince1970: 1_800_000_000), future = base.addingTimeInterval(120)
        func fixture() -> (SystemReminderNotifications, ReminderScheduler) {
            let boundary = SystemReminderNotifications(); return (boundary, ReminderScheduler(notifications: boundary, now: { base }))
        }
        func fails(_ expected: ReminderError, _ operation: () async throws -> Void) async -> Bool {
            do { try await operation(); return false } catch { return error as? ReminderError == expected }
        }
        do {
            let (b,s) = fixture(); b.status = .denied
            let denied = await fails(.permissionDenied) { _ = try await s.create(title: "Fixture", notes: "", date: future) }
            record("permission denial causes no add and clears busy", denied && b.adds == 0 && !s.isBusy && s.authorization == .denied)
        }
        do {
            let (b,s) = fixture(); let created = try await s.create(title: "Fixture", notes: "", date: future)
            record("successful create confirmed by retained queue", s.reminders == [created] && b.adds == 1 && !s.isBusy)
            try await s.cancel(id: created.id)
            record("cancellation confirmed by empty queue", b.queue.isEmpty && s.reminders.isEmpty && !s.isBusy)
        }
        do {
            let (b,s) = fixture(); b.throwAfterAdd = true
            let result = try await s.create(title: "Fixture", notes: "", date: future)
            record("ambiguous add callback returns actually retained reminder", s.reminders == [result] && b.adds == 1 && !s.isBusy)
        }
        do {
            let (b,s) = fixture(); b.retainAdd = false
            let failed = await fails(.notScheduled) { _ = try await s.create(title: "Fixture", notes: "", date: future) }
            record("successful callback without retention is not success", failed && s.reminders.isEmpty && !s.isBusy)
        }
        do {
            let (b,s) = fixture()
            b.queue = (0..<48).map { LocalReminder(id: UUID(), title: "Fixture \($0)", notes: "", date: future) }
            let failed = await fails(.capacityReached) { _ = try await s.create(title: "Fixture", notes: "", date: future) }
            record("48 reminder capacity blocks add", failed && b.adds == 0 && s.reminders.count == 48 && !s.isBusy)
        }
        do {
            let (b,s) = fixture(); b.unrelated = 64
            let failed = await fails(.systemCapacityReached) { _ = try await s.create(title: "Fixture", notes: "", date: future) }
            record("64 total pending capacity blocks add", failed && b.adds == 0 && !s.isBusy)
        }
        do {
            let b = SystemReminderNotifications(); b.status = .notDetermined
            var now = base
            let s = ReminderScheduler(notifications: b, now: { now })
            b.permissionAction = { now = future.addingTimeInterval(1) }
            do { _ = try await s.create(title: "Fixture", notes: "", date: future); record("date revalidated after permission delay", false) }
            catch { record("date revalidated after permission delay", error is ReminderError && b.adds == 0 && !s.isBusy) }
        }
        do {
            let (b,s) = fixture(); let created = try await s.create(title: "Fixture", notes: "", date: future); b.refuseRemove = true
            let failed = await fails(.cancellationFailed) { try await s.cancel(id: created.id) }
            record("refused cancellation retains visible reminder", failed && s.reminders == [created] && !s.isBusy)
        }
        do {
            let (b,s) = fixture(); b.status = .notDetermined; b.holdPermission = true
            let first = Task { @MainActor in try await s.create(title: "First", notes: "", date: future) }
            for _ in 0..<100 where b.permissionWait == nil { await Task.yield() }
            let held = b.permissionWait != nil
            let denied = await fails(.busy) { _ = try await s.create(title: "Second", notes: "", date: future) }
            b.permissionWait?.resume(); b.permissionWait = nil
            _ = try await first.value
            record("concurrent operation refused while permission suspended", held && denied && b.adds == 1 && !s.isBusy)
        }
        do {
            let b = SystemReminderNotifications(); b.roundtripUnixDate = true
            let fractional = Date(timeIntervalSinceReferenceDate: 800_000_120.0000001)
            let s = ReminderScheduler(notifications: b, now: { fractional.addingTimeInterval(-120) })
            do {
                let value = try await s.create(title: "Fractional", notes: "", date: fractional)
                record("Unix timestamp roundtrip confirms fractional date", b.queue == [value] && s.reminders == [value])
            } catch { record("Unix timestamp roundtrip confirms fractional date", false) }
        }
        for fraction in [0.0000001, 0.375] {
            let selected = Date(timeIntervalSinceReferenceDate: 800_000_120 + fraction)
            let components = ProductionReminderComponents.evaluate(selected)
            let restored = components.calendar?.date(from: components)
            let valid = restored.map { $0 >= selected && $0.timeIntervalSince(selected) <= 1 && $0.timeIntervalSince1970.rounded(.down) == $0.timeIntervalSince1970 } ?? false
            record("exact legacy components UTC whole-second never early fraction \(fraction)", valid && components.calendar?.identifier == .gregorian && components.timeZone?.secondsFromGMT(for: selected) == 0)
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["checks":checks,"osNotificationDeliveryVerified":false,"nativeIPhoneVerified":false], options: [.prettyPrinted,.sortedKeys]), as: UTF8.self))
        if checks.contains(where: { $0["passed"] as? Bool != true }) { exit(1) }
    }
}
