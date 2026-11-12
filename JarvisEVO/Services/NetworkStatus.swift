import Foundation
import Network
import Observation

@MainActor @Observable
final class NetworkStatus {
    /// Nil means the first reachability result has not arrived, not that the device is offline.
    private(set) var isOnline: Bool?
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.jarvisevo.network-status")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in self?.isOnline = connected }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
