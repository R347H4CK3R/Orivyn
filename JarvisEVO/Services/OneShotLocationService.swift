import Foundation
import CoreLocation
import Observation

@MainActor
protocol LocationDriver: AnyObject {
    func start(completion: @escaping @MainActor (Result<LocationSnapshot, any Error>) -> Void)
    func cancel()
}

/// A bounded, foreground request. It never persists, geocodes, logs or transmits coordinates.
@MainActor @Observable
final class OneShotLocationService {
    private(set) var snapshot: LocationSnapshot?
    private(set) var error: String?
    private(set) var isBusy = false
    @ObservationIgnored private let driverFactory: @MainActor () -> any LocationDriver
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private var driver: (any LocationDriver)?
    @ObservationIgnored private var operation: UUID?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    init(driverFactory: @escaping @MainActor () -> any LocationDriver = { SystemLocationDriver() },
         now: @escaping () -> Date = Date.init, timeout: Duration = .seconds(30)) {
        self.driverFactory = driverFactory; self.now = now; self.timeout = timeout
    }

    func request() {
        guard !isBusy else { return }
        let id = UUID(), next = driverFactory()
        operation = id; driver = next; isBusy = true; snapshot = nil; error = nil
        timeoutTask = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(.failure(LocationToolError.timedOut), id: id)
        }
        next.start { [weak self] result in self?.finish(result, id: id) }
    }

    func cancel(clearResult: Bool = true) {
        operation = nil; isBusy = false
        timeoutTask?.cancel(); timeoutTask = nil
        let previous = driver; driver = nil; previous?.cancel()
        error = nil
        if clearResult { snapshot = nil }
    }

    private func finish(_ result: Result<LocationSnapshot, any Error>, id: UUID) {
        guard operation == id else { return }
        cancel(clearResult: true)
        do { snapshot = try result.get().validated(now: now()) }
        catch { self.error = error.localizedDescription }
    }
}

/// Created on the main run loop only after a tap. Core Location delivers delegate
/// calls on that run loop; the conformance acknowledges that SDK delegate contract.
@MainActor
private final class SystemLocationDriver: NSObject, LocationDriver, @preconcurrency CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var completion: (@MainActor (Result<LocationSnapshot, any Error>) -> Void)?
    private var requestedPermission = false
    private var requestedLocation = false

    func start(completion: @escaping @MainActor (Result<LocationSnapshot, any Error>) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion
        let manager = CLLocationManager()
        self.manager = manager
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        advance(manager)
    }

    func cancel() {
        completion = nil
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
    }

    private func advance(_ manager: CLLocationManager) {
        guard self.manager === manager, completion != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            guard !requestedPermission else { return }
            requestedPermission = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            guard !requestedLocation else { return }
            requestedLocation = true
            manager.requestLocation()
        case .denied, .restricted: complete(.failure(LocationToolError.denied))
        @unknown default: complete(.failure(LocationToolError.unavailable))
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { advance(manager) }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard self.manager === manager, let location = locations.last else { return }
        complete(.success(LocationSnapshot(latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy, timestamp: location.timestamp)))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard self.manager === manager else { return }
        complete(.failure((error as? CLError)?.code == .denied ? LocationToolError.denied : LocationToolError.unavailable))
    }
    private func complete(_ result: Result<LocationSnapshot, any Error>) {
        let callback = completion
        cancel()
        callback?(result)
    }
}
