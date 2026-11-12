import XCTest
@testable import JarvisEVO

@MainActor
final class OneShotLocationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNoHardwareAccessUntilExplicitRequestAndRepeatedTapIsIgnored() {
        let driver = FakeLocationDriver()
        let service = OneShotLocationService(driverFactory: { driver }, now: { self.now })
        XCTAssertEqual(driver.starts, 0); XCTAssertNil(service.snapshot); XCTAssertFalse(service.isBusy)
        service.request(); service.request()
        XCTAssertEqual(driver.starts, 1); XCTAssertTrue(service.isBusy)
        service.cancel()
    }

    func testValidatedSnapshotCompletesOneRequestAndStopsDriver() throws {
        let driver = FakeLocationDriver()
        let service = OneShotLocationService(driverFactory: { driver }, now: { self.now })
        service.request()
        driver.respond(.success(validSnapshot))
        XCTAssertEqual(service.snapshot, validSnapshot)
        XCTAssertFalse(service.isBusy); XCTAssertNil(service.error)
        XCTAssertEqual(driver.cancels, 1)
    }

    func testDeniedPermissionIsNotSuccessfulLocation() {
        let driver = FakeLocationDriver()
        let service = OneShotLocationService(driverFactory: { driver }, now: { self.now })
        service.request(); driver.respond(.failure(LocationToolError.denied))
        XCTAssertFalse(service.isBusy); XCTAssertNil(service.snapshot)
        XCTAssertEqual(service.error, LocationToolError.denied.localizedDescription)
    }

    func testCancelClearsSnapshotAndLateCallbackCannotResurrectRequest() {
        let driver = FakeLocationDriver()
        let service = OneShotLocationService(driverFactory: { driver }, now: { self.now })
        service.request(); service.cancel()
        driver.respond(.success(validSnapshot))
        XCTAssertNil(service.snapshot); XCTAssertFalse(service.isBusy); XCTAssertNil(service.error)
    }

    func testOldCallbackCannotFinishOrOverwriteNewRequest() {
        let first = FakeLocationDriver(), second = FakeLocationDriver()
        var issued = 0
        let service = OneShotLocationService(driverFactory: { issued += 1; return issued == 1 ? first : second }, now: { self.now })
        service.request(); service.cancel(); service.request()
        first.respond(.success(validSnapshot))
        XCTAssertTrue(service.isBusy); XCTAssertNil(service.snapshot)
        let replacement = LocationSnapshot(latitude: 48.8566, longitude: 2.3522, accuracy: 250, timestamp: now)
        second.respond(.success(replacement))
        XCTAssertFalse(service.isBusy); XCTAssertEqual(service.snapshot, replacement)
    }

    func testInvalidCoordinatesAccuracyAndTimestampsAreRejected() throws {
        let invalid = [
            LocationSnapshot(latitude: .nan, longitude: 0, accuracy: 1, timestamp: now),
            LocationSnapshot(latitude: 91, longitude: 0, accuracy: 1, timestamp: now),
            LocationSnapshot(latitude: 0, longitude: -181, accuracy: 1, timestamp: now),
            LocationSnapshot(latitude: 0, longitude: .infinity, accuracy: 1, timestamp: now),
            LocationSnapshot(latitude: 0, longitude: 0, accuracy: -1, timestamp: now),
            LocationSnapshot(latitude: 0, longitude: 0, accuracy: .infinity, timestamp: now),
            LocationSnapshot(latitude: 0, longitude: 0, accuracy: 1, timestamp: now.addingTimeInterval(-61)),
            LocationSnapshot(latitude: 0, longitude: 0, accuracy: 1, timestamp: now.addingTimeInterval(6)),
            LocationSnapshot(latitude: 0, longitude: 0, accuracy: 1, timestamp: Date(timeIntervalSince1970: .nan))
        ]
        for value in invalid {
            let driver = FakeLocationDriver()
            let service = OneShotLocationService(driverFactory: { driver }, now: { self.now })
            service.request(); driver.respond(.success(value))
            XCTAssertNil(service.snapshot); XCTAssertNotNil(service.error); XCTAssertFalse(service.isBusy)
        }
    }

    func testBoundaryCoordinateAndReducedAccuracyRemainUsable() {
        let driver = FakeLocationDriver()
        let service = OneShotLocationService(driverFactory: { driver }, now: { self.now })
        service.request()
        let value = LocationSnapshot(latitude: -90, longitude: 180, accuracy: 5_000, timestamp: now.addingTimeInterval(-60))
        driver.respond(.success(value))
        XCTAssertEqual(service.snapshot, value, "Approximate location is not an error and must retain its true accuracy.")
    }

    func testTimeoutStopsRequestAndIgnoresLateSuccess() async throws {
        let driver = FakeLocationDriver()
        let service = OneShotLocationService(driverFactory: { driver }, now: { self.now }, timeout: .milliseconds(1))
        service.request()
        let deadline = ContinuousClock.now + .seconds(2)
        while service.isBusy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(service.isBusy)
        XCTAssertEqual(service.error, LocationToolError.timedOut.localizedDescription)
        driver.respond(.success(validSnapshot)); XCTAssertNil(service.snapshot)
        XCTAssertEqual(driver.cancels, 1)
    }

    func testCancelPreservingDisplayedResultDoesNotPreserveInFlightOwnership() {
        let driver = FakeLocationDriver()
        let service = OneShotLocationService(driverFactory: { driver }, now: { self.now })
        service.request(); driver.respond(.success(validSnapshot))
        service.cancel(clearResult: false)
        XCTAssertEqual(service.snapshot, validSnapshot)
        service.cancel(); XCTAssertNil(service.snapshot)
    }

    private var validSnapshot: LocationSnapshot {
        LocationSnapshot(latitude: 37.3349, longitude: -122.009, accuracy: 25, timestamp: now)
    }
}

@MainActor
private final class FakeLocationDriver: LocationDriver {
    private var callback: (@MainActor (Result<LocationSnapshot, any Error>) -> Void)?
    private(set) var starts = 0
    private(set) var cancels = 0
    func start(completion: @escaping @MainActor (Result<LocationSnapshot, any Error>) -> Void) {
        starts += 1; callback = completion
    }
    func cancel() { cancels += 1 }
    func respond(_ value: Result<LocationSnapshot, any Error>) { callback?(value) }
}
