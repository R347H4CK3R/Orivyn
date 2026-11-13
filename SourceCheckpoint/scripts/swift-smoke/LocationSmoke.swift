import Foundation
import Glibc

// Synthetic boundary only. No CoreLocation, permissions, hardware or real coordinates.
@MainActor final class SystemLocationDriver: LocationDriver {
    var starts = 0, cancels = 0
    var synchronous: Result<LocationSnapshot, any Error>?
    var callback: (@MainActor (Result<LocationSnapshot, any Error>) -> Void)?
    func start(completion: @escaping @MainActor (Result<LocationSnapshot, any Error>) -> Void) {
        starts += 1; callback = completion
        if let synchronous { completion(synchronous) }
    }
    func cancel() { cancels += 1 }
    // Intentionally retains callback after cancel to test stale delivery fencing.
    func emit(_ result: Result<LocationSnapshot, any Error>) { callback?(result) }
}
@main struct LocationSmoke {
    @MainActor static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let valid = LocationSnapshot(latitude: 1, longitude: 2, accuracy: 25, timestamp: now)
        var checks: [[String: Any]] = []
        func record(_ name: String, _ passed: Bool) { checks.append(["check":name,"passed":passed]) }
        do {
            let d = SystemLocationDriver(); var factories = 0
            let s = OneShotLocationService(driverFactory: { factories += 1; return d }, now: { now })
            record("no driver created before explicit request", factories == 0 && !s.isBusy && s.snapshot == nil)
            s.request(); s.request()
            record("busy repeated request creates only one driver", factories == 1 && d.starts == 1 && s.isBusy)
            s.cancel()
        }
        do {
            let d = SystemLocationDriver(); d.synchronous = .success(valid)
            let s = OneShotLocationService(driverFactory: { d }, now: { now }, timeout: .milliseconds(1))
            s.request()
            record("synchronous callback completes and cancels driver", s.snapshot == valid && s.error == nil && !s.isBusy && d.cancels == 1)
            try await Task.sleep(for: .milliseconds(20))
            record("cancelled timeout cannot overwrite synchronous success", s.snapshot == valid && s.error == nil && d.cancels == 1)
            s.cancel(clearResult: false)
            record("explicit preserve-result cancellation keeps only displayed snapshot", s.snapshot == valid && !s.isBusy)
            s.cancel(); record("default cancellation clears displayed snapshot", s.snapshot == nil && s.error == nil)
        }
        do {
            let d = SystemLocationDriver(), next = SystemLocationDriver(); var factories = 0
            let s = OneShotLocationService(driverFactory: { factories += 1; return factories == 1 ? d : next }, now: { now })
            s.request(); s.cancel(); d.emit(.success(valid))
            record("late callback after cancel cannot resurrect snapshot", s.snapshot == nil && !s.isBusy && s.error == nil && d.cancels == 1)
            s.request(); d.emit(.success(valid))
            record("previous owner callback cannot finish replacement request", s.isBusy && s.snapshot == nil && next.cancels == 0)
            let replacement = LocationSnapshot(latitude: 3, longitude: 4, accuracy: 50, timestamp: now)
            next.emit(.success(replacement)); d.emit(.failure(LocationToolError.denied))
            record("replacement success survives stale failure", s.snapshot == replacement && s.error == nil && !s.isBusy && next.cancels == 1)
        }
        do {
            let d = SystemLocationDriver()
            let s = OneShotLocationService(driverFactory: { d }, now: { now })
            s.request(); d.emit(.failure(LocationToolError.denied))
            record("permission denial is explicit failure not location", s.snapshot == nil && !s.isBusy && s.error == LocationToolError.denied.localizedDescription && d.cancels == 1)
        }
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
        for (index,value) in invalid.enumerated() {
            let d = SystemLocationDriver(); let s = OneShotLocationService(driverFactory: { d }, now: { now })
            s.request(); d.emit(.success(value))
            record("invalid synthetic snapshot rejected case \(index)", s.snapshot == nil && !s.isBusy && s.error == LocationToolError.invalidResult.localizedDescription && d.cancels == 1)
        }
        do {
            let d = SystemLocationDriver(); let s = OneShotLocationService(driverFactory: { d }, now: { now })
            let boundary = LocationSnapshot(latitude: -90, longitude: 180, accuracy: 5000, timestamp: now.addingTimeInterval(-60))
            s.request(); d.emit(.success(boundary))
            record("valid boundary and reduced accuracy preserved exactly", s.snapshot == boundary && s.error == nil)
        }
        do {
            let d = SystemLocationDriver(); let s = OneShotLocationService(driverFactory: { d }, now: { now }, timeout: .milliseconds(1))
            s.request()
            let deadline = ContinuousClock.now + .seconds(2)
            while s.isBusy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
            d.emit(.success(valid))
            record("timeout stops driver and ignores late success", !s.isBusy && s.snapshot == nil && s.error == LocationToolError.timedOut.localizedDescription && d.cancels == 1)
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["checks":checks,"syntheticLocationBoundary":true,"hardwareOrPermissionsVerified":false,"nativeIPhoneVerified":false], options: [.prettyPrinted,.sortedKeys]), as: UTF8.self))
        if checks.contains(where: { $0["passed"] as? Bool != true }) { exit(1) }
    }
}
