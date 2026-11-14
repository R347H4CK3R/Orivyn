import XCTest
import UserNotifications
@testable import JarvisEVO

@MainActor
final class ReminderSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNotificationPayloadRoundTripsLiteralIdentityAndUTCDate() throws {
        let id = UUID(uuidString: "BBAB022A-87F2-4411-913A-7654B4B9B38B")!
        let reminder = LocalReminder(id: id, title: "Read the book", notes: "Chapter 3", date: now.addingTimeInterval(120))
        let request = SystemReminderNotifications.request(for: reminder)
        XCTAssertEqual(request.identifier, "orivyn.reminder.BBAB022A-87F2-4411-913A-7654B4B9B38B")
        XCTAssertEqual(request.content.title, "Read the book")
        XCTAssertEqual(request.content.body, "Chapter 3")
        XCTAssertEqual(request.content.userInfo["owner"] as? String, "orivyn.local-reminder")
        XCTAssertEqual(request.content.userInfo["version"] as? Int, 1)
        XCTAssertEqual(request.content.userInfo["id"] as? String, "BBAB022A-87F2-4411-913A-7654B4B9B38B")
        XCTAssertFalse(try XCTUnwrap(request.trigger).repeats)
        XCTAssertNotNil(request.content.sound)
        XCTAssertEqual(SystemReminderNotifications.reminder(from: request, now: now), reminder)
    }

    func testFractionalDateRoundTripUsesNextWholeSecondNeverEarlier() throws {
        let reminder = try LocalReminder.validated(title: "Read", notes: "", date: Date(timeIntervalSince1970: 1_800_000_060.375), now: now)
        let request = SystemReminderNotifications.request(for: reminder)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fireDate = try XCTUnwrap(calendar.date(from: trigger.dateComponents))
        XCTAssertEqual(fireDate, Date(timeIntervalSince1970: 1_800_000_061))
        XCTAssertEqual(SystemReminderNotifications.reminder(from: request, now: now), reminder)
    }

    func testFractionalEpochConversionDoesNotBreakOSConfirmation() throws {
        let selected = Date(timeIntervalSinceReferenceDate: 800_000_120.0000001)
        let current = selected.addingTimeInterval(-120)
        let reminder = try LocalReminder.validated(title: "Precise selection", notes: "", date: selected, now: current)
        XCTAssertGreaterThanOrEqual(reminder.date, selected)
        XCTAssertEqual(reminder.date, Date(timeIntervalSince1970: reminder.date.timeIntervalSince1970))
        let request = SystemReminderNotifications.request(for: reminder)
        XCTAssertEqual(SystemReminderNotifications.reminder(from: request, now: current), reminder)
    }

    func testLegacySubULPFractionNeverSchedulesBeforeStoredDate() throws {
        let selected = Date(timeIntervalSinceReferenceDate: 800_000_120.0000001)
        let legacy = LocalReminder(id: UUID(), title: "Legacy", notes: "", date: selected)
        let request = SystemReminderNotifications.request(for: legacy)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(calendar.date(from: trigger.dateComponents)), selected)
    }

    func testAdapterIgnoresUnrelatedMalformedAndRepeatingRequests() throws {
        let reminder = try sample()
        let valid = SystemReminderNotifications.request(for: reminder)
        let content = try XCTUnwrap(valid.content.mutableCopy() as? UNMutableNotificationContent)
        let variants: [(String, [AnyHashable: Any], UNNotificationTrigger?)] = [
            ("another.feature", content.userInfo, valid.trigger),
            (valid.identifier, [:], valid.trigger),
            (valid.identifier, ["owner": "other", "version": 1, "id": reminder.id.uuidString], valid.trigger),
            (valid.identifier, ["owner": "orivyn.local-reminder", "version": 2, "id": reminder.id.uuidString], valid.trigger),
            (valid.identifier, ["owner": "orivyn.local-reminder", "version": 1, "id": UUID().uuidString], valid.trigger),
            (valid.identifier, content.userInfo, nil),
            (valid.identifier, content.userInfo, UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: true))
        ]
        for (identifier, userInfo, trigger) in variants {
            let modified = try XCTUnwrap(content.mutableCopy() as? UNMutableNotificationContent)
            modified.userInfo = userInfo
            let request = UNNotificationRequest(identifier: identifier, content: modified, trigger: trigger)
            XCTAssertNil(SystemReminderNotifications.reminder(from: request, now: now))
        }
    }

    func testAdapterRejectsExpiredOversizedAndMismatchedPayloads() throws {
        let reminder = try sample()
        let valid = SystemReminderNotifications.request(for: reminder)
        XCTAssertNil(SystemReminderNotifications.reminder(from: valid, now: now.addingTimeInterval(120)))
        let content = try XCTUnwrap(valid.content.mutableCopy() as? UNMutableNotificationContent)
        content.body = String(repeating: "x", count: 2_001)
        XCTAssertNil(SystemReminderNotifications.reminder(from: UNNotificationRequest(identifier: valid.identifier, content: content, trigger: valid.trigger), now: now))
        content.body = ""
        content.userInfo["date"] = now.addingTimeInterval(600).timeIntervalSince1970
        XCTAssertNil(SystemReminderNotifications.reminder(from: UNNotificationRequest(identifier: valid.identifier, content: content, trigger: valid.trigger), now: now))
    }

    func testRefreshAndRelaunchUseActualQueueWithoutAskingPermission() async throws {
        let client = TestReminderNotifications()
        let later = try sample("Later", offset: 120), earlier = try sample("Earlier", offset: 60)
        client.stored = [later, earlier]
        let scheduler = makeScheduler(client)
        await scheduler.refresh()
        XCTAssertEqual(scheduler.reminders.map(\.title), ["Earlier", "Later"])
        XCTAssertEqual(client.permissionRequests, 0)
        client.stored = [later] // A reminder disappeared from the OS queue, not a local cache.
        let relaunched = makeScheduler(client)
        await relaunched.refresh()
        XCTAssertEqual(relaunched.reminders.map(\.id), [later.id])
        XCTAssertEqual(client.permissionRequests, 0)
    }

    func testInvalidInputNeverRequestsPermissionOrSchedules() async {
        let client = TestReminderNotifications()
        let actual = makeScheduler(client)
        do { _ = try await actual.create(title: " ", notes: "", date: now.addingTimeInterval(60)); XCTFail("Accepted an empty title") } catch { }
        XCTAssertEqual(client.permissionRequests, 0)
        XCTAssertTrue(client.stored.isEmpty)
        XCTAssertTrue(actual.reminders.isEmpty)
        XCTAssertFalse(actual.isBusy)
    }

    func testDeniedPermissionLeavesExistingQueueIntact() async throws {
        let client = TestReminderNotifications()
        client.status = .denied; client.stored = [try sample("Keep")]
        let scheduler = makeScheduler(client)
        do { _ = try await scheduler.create(title: "Denied", notes: "", date: now.addingTimeInterval(60)); XCTFail("Scheduled without permission") }
        catch { XCTAssertEqual(error as? ReminderError, .permissionDenied) }
        XCTAssertEqual(client.stored.map(\.title), ["Keep"])
        XCTAssertEqual(scheduler.reminders.map(\.title), ["Keep"])
        XCTAssertEqual(client.permissionRequests, 0)
    }

    func testPermissionRefusalDoesNotReportAnOptimisticReminder() async {
        let client = TestReminderNotifications(); client.grantPermission = false
        let scheduler = makeScheduler(client)
        do { _ = try await scheduler.create(title: "Denied", notes: "", date: now.addingTimeInterval(60)); XCTFail("Scheduled after refusal") }
        catch { XCTAssertEqual(error as? ReminderError, .permissionDenied) }
        XCTAssertTrue(scheduler.reminders.isEmpty)
        XCTAssertTrue(client.stored.isEmpty)
        XCTAssertEqual(client.permissionRequests, 1)
    }

    func testPermissionRefusalReconcilesQueueChangesWhilePromptWasOpen() async throws {
        let client = TestReminderNotifications(); client.holdPermission = true; client.grantPermission = false
        client.stored = [try sample("Previously pending")]
        let scheduler = makeScheduler(client)
        let task = Task { try await scheduler.create(title: "Denied", notes: "", date: now.addingTimeInterval(60)) }
        await client.waitUntilPermissionRequest()
        client.stored = []
        client.finishPermission()
        do { _ = try await task.value; XCTFail("Scheduled after denial") }
        catch { XCTAssertEqual(error as? ReminderError, .permissionDenied) }
        XCTAssertTrue(scheduler.reminders.isEmpty)
        XCTAssertEqual(scheduler.authorization, .denied)
    }

    func testSuccessfulCreationIsOnlyListedAfterActualQueueContainsIt() async throws {
        let client = TestReminderNotifications()
        let actual = makeScheduler(client)
        let reminder = try await actual.create(title: "  Read  ", notes: "Chapter 3", date: now.addingTimeInterval(60))
        XCTAssertEqual(actual.reminders, [reminder])
        XCTAssertEqual(client.stored, [reminder])
        XCTAssertEqual(reminder.title, "Read")
        XCTAssertEqual(client.permissionRequests, 1)
        XCTAssertFalse(actual.isBusy)
    }

    func testAddErrorRefreshesQueueAndDoesNotInventSuccess() async {
        let client = TestReminderNotifications(); client.status = .authorized; client.failAdd = true
        let scheduler = makeScheduler(client)
        do { _ = try await scheduler.create(title: "Read", notes: "", date: now.addingTimeInterval(60)); XCTFail("Ignored OS error") } catch { }
        XCTAssertTrue(scheduler.reminders.isEmpty)
        XCTAssertTrue(client.stored.isEmpty)
        XCTAssertFalse(scheduler.isBusy)
    }

    func testAcceptedButAbsentRequestIsNotReportedAsScheduled() async {
        let client = TestReminderNotifications(); client.status = .authorized; client.dropAdd = true
        let scheduler = makeScheduler(client)
        do { _ = try await scheduler.create(title: "Read", notes: "", date: now.addingTimeInterval(60)); XCTFail("Assumed the OS retained the request") }
        catch { XCTAssertEqual(error as? ReminderError, .notScheduled) }
        XCTAssertTrue(scheduler.reminders.isEmpty)
    }

    func testReportedAddErrorWithConfirmedQueueEntryDoesNotDuplicateIt() async throws {
        let client = TestReminderNotifications(); client.status = .authorized; client.errorAfterAdd = true
        let scheduler = makeScheduler(client)
        let reminder = try await scheduler.create(title: "Read", notes: "", date: now.addingTimeInterval(60))
        XCTAssertEqual(scheduler.reminders, [reminder])
        XCTAssertEqual(client.stored.count, 1)
    }

    func testExistingOwnedCapacityIsCheckedBeforePermission() async throws {
        let client = TestReminderNotifications()
        client.stored = try (0..<48).map { try sample("Reminder \($0)") }
        let scheduler = makeScheduler(client)
        do { _ = try await scheduler.create(title: "Overflow", notes: "", date: now.addingTimeInterval(60)); XCTFail("Exceeded owned capacity") }
        catch { XCTAssertEqual(error as? ReminderError, .capacityReached) }
        XCTAssertEqual(client.stored.count, 48)
        XCTAssertEqual(client.permissionRequests, 0)
    }

    func testUnrelatedOSQueueCapacityIsNotEvictedToMakeRoom() async {
        let client = TestReminderNotifications(); client.status = .authorized; client.unrelatedCount = 64
        let scheduler = makeScheduler(client)
        do { _ = try await scheduler.create(title: "Overflow", notes: "", date: now.addingTimeInterval(60)); XCTFail("Risked evicting unrelated requests") }
        catch { XCTAssertEqual(error as? ReminderError, .systemCapacityReached) }
        XCTAssertEqual(client.unrelatedCount, 64)
        XCTAssertTrue(client.stored.isEmpty)
    }

    func testConcurrentCreateCannotReplaceOrExceedPendingOperation() async throws {
        let client = TestReminderNotifications(); client.holdPermission = true
        let scheduler = makeScheduler(client)
        let first = Task { try await scheduler.create(title: "First", notes: "", date: now.addingTimeInterval(60)) }
        await client.waitUntilPermissionRequest()
        do { _ = try await scheduler.create(title: "Second", notes: "", date: now.addingTimeInterval(60)); XCTFail("Concurrent scheduling allowed") }
        catch { XCTAssertEqual(error as? ReminderError, .busy) }
        await scheduler.refresh() // Must not release the first operation's ownership.
        XCTAssertTrue(scheduler.isBusy)
        client.finishPermission()
        _ = try await first.value
        XCTAssertEqual(scheduler.reminders.map(\.title), ["First"])
    }

    func testCapacityIsRecheckedAfterPermissionWait() async throws {
        let client = TestReminderNotifications(); client.holdPermission = true
        let scheduler = makeScheduler(client)
        let task = Task { try await scheduler.create(title: "First", notes: "", date: now.addingTimeInterval(60)) }
        await client.waitUntilPermissionRequest()
        client.stored = try (0..<48).map { try sample("External change \($0)") }
        client.finishPermission()
        do { _ = try await task.value; XCTFail("Used stale capacity") }
        catch { XCTAssertEqual(error as? ReminderError, .capacityReached) }
        XCTAssertEqual(client.stored.count, 48)
    }

    func testDateThatExpiresDuringPermissionPromptIsNotScheduled() async {
        let client = TestReminderNotifications(); client.holdPermission = true
        var clock = now
        let scheduler = ReminderScheduler(notifications: client, now: { clock })
        let task = Task { try await scheduler.create(title: "Soon", notes: "", date: now.addingTimeInterval(10)) }
        await client.waitUntilPermissionRequest()
        clock = now.addingTimeInterval(8)
        client.finishPermission()
        do { _ = try await task.value; XCTFail("Scheduled a stale date") } catch { }
        XCTAssertTrue(client.stored.isEmpty)
    }

    func testCanceledTaskWhilePermissionIsPendingDoesNotSchedule() async {
        let client = TestReminderNotifications(); client.holdPermission = true
        let scheduler = makeScheduler(client)
        let task = Task { try await scheduler.create(title: "Canceled", notes: "", date: now.addingTimeInterval(60)) }
        await client.waitUntilPermissionRequest()
        task.cancel()
        client.finishPermission()
        do { _ = try await task.value; XCTFail("Scheduled after task cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(client.stored.isEmpty)
        XCTAssertFalse(scheduler.isBusy)
    }

    func testCancelOnlyRemovesSelectedOwnedReminderAndReconciles() async throws {
        let client = TestReminderNotifications()
        let first = try sample("Cancel"), second = try sample("Keep")
        client.stored = [first, second]; client.unrelatedCount = 2
        let scheduler = makeScheduler(client)
        try await scheduler.cancel(id: first.id)
        XCTAssertEqual(scheduler.reminders, [second])
        XCTAssertEqual(client.stored, [second])
        XCTAssertEqual(client.unrelatedCount, 2)
        XCTAssertEqual(client.removedIdentifiers, ["orivyn.reminder.\(first.id.uuidString)"])
    }

    func testCancelUnknownIdentityDoesNotRemoveAnything() async throws {
        let client = TestReminderNotifications(); client.stored = [try sample("Keep")]; client.unrelatedCount = 3
        let scheduler = makeScheduler(client)
        do { try await scheduler.cancel(id: UUID()); XCTFail("Canceled a non-owned identity") }
        catch { XCTAssertEqual(error as? ReminderError, .notFound) }
        XCTAssertEqual(client.stored.count, 1)
        XCTAssertEqual(client.unrelatedCount, 3)
        XCTAssertTrue(client.removedIdentifiers.isEmpty)
    }

    func testFailedCancellationDoesNotOptimisticallyHidePendingReminder() async throws {
        let client = TestReminderNotifications(); client.ignoreRemove = true
        let reminder = try sample(); client.stored = [reminder]
        let scheduler = makeScheduler(client)
        do { try await scheduler.cancel(id: reminder.id); XCTFail("Ignored retained notification") }
        catch { XCTAssertEqual(error as? ReminderError, .cancellationFailed) }
        XCTAssertEqual(scheduler.reminders, [reminder])
    }

    private func sample(_ title: String = "Read", offset: TimeInterval = 60) throws -> LocalReminder {
        try LocalReminder.validated(title: title, notes: "", date: now.addingTimeInterval(offset), now: now)
    }
    private func makeScheduler(_ client: TestReminderNotifications) -> ReminderScheduler {
        let date = now
        return ReminderScheduler(notifications: client, now: { date })
    }
}

/// The notification center is an OS side-effect boundary. This test-only adapter
/// lets denial, retained requests and races be deterministic without permission UI.
@MainActor
private final class TestReminderNotifications: ReminderNotifications {
    var status: ReminderAuthorization = .notDetermined
    var grantPermission = true
    var stored: [LocalReminder] = []
    var unrelatedCount = 0
    var failAdd = false, dropAdd = false, errorAfterAdd = false, ignoreRemove = false
    var permissionRequests = 0
    var removedIdentifiers: [String] = []
    var holdPermission = false
    private var permissionContinuation: CheckedContinuation<Bool, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    func authorizationStatus() async -> ReminderAuthorization { status }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        if holdPermission {
            return await withCheckedContinuation { continuation in
                permissionContinuation = continuation
                startedContinuation?.resume(); startedContinuation = nil
            }
        }
        status = grantPermission ? .authorized : .denied
        return grantPermission
    }
    func waitUntilPermissionRequest() async {
        if permissionContinuation != nil { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }
    func finishPermission() {
        status = grantPermission ? .authorized : .denied
        permissionContinuation?.resume(returning: grantPermission); permissionContinuation = nil
    }
    func pending() async -> ReminderNotificationQueue {
        ReminderNotificationQueue(reminders: stored, totalPendingCount: stored.count + unrelatedCount)
    }
    func add(_ reminder: LocalReminder) async throws {
        if failAdd { throw CocoaError(.fileWriteUnknown) }
        if !dropAdd { stored.append(reminder) }
        if errorAfterAdd { throw CocoaError(.fileWriteUnknown) }
    }
    func removePending(identifier: String) async {
        removedIdentifiers.append(identifier)
        if !ignoreRemove { stored.removeAll { "orivyn.reminder.\($0.id.uuidString)" == identifier } }
    }
}
