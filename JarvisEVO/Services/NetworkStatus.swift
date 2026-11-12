import Foundation
import Network
import Observation

@MainActor @Observable
final class NetworkStatus {
    /// Nil means the first reachability result has not arrived, not that the device is offline.
    private(set) var isOnline: Bool?
    private(set) var automaticDownloadNetwork: AutomaticDownloadNetwork = .unknown
    var onAutomaticPathChange: (@MainActor (AutomaticDownloadNetwork) -> Void)?
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.jarvisevo.network-status")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let automatic: AutomaticDownloadNetwork
            if !connected { automatic = .offline }
            else if path.isConstrained { automatic = .constrained }
            else if path.usesInterfaceType(.cellular) { automatic = .cellular }
            else if path.isExpensive { automatic = .constrained }
            else if path.usesInterfaceType(.wifi) { automatic = .wifi }
            else if path.usesInterfaceType(.wiredEthernet) { automatic = .wired }
            else { automatic = .unknown }
            Task { @MainActor [weak self] in
                self?.isOnline = connected
                self?.automaticDownloadNetwork = automatic
                self?.onAutomaticPathChange?(automatic)
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
