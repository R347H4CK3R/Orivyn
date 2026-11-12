import Foundation

/// Policy is enforced by URLSession for the complete request, not just a path snapshot.
enum ModelDownloadPolicy: Sendable {
    case userInitiated, automaticWiFi, automaticCellular
    func configuration() -> URLSessionConfiguration {
        let result = URLSessionConfiguration.ephemeral
        result.timeoutIntervalForRequest = 120
        result.timeoutIntervalForResource = 3_600
        result.urlCache = nil
        result.waitsForConnectivity = false
        switch self {
        case .userInitiated:
            result.allowsCellularAccess = true
            result.allowsExpensiveNetworkAccess = true
            result.allowsConstrainedNetworkAccess = true
        case .automaticWiFi:
            result.allowsCellularAccess = false
            result.allowsExpensiveNetworkAccess = false
            result.allowsConstrainedNetworkAccess = false
        case .automaticCellular:
            result.allowsCellularAccess = true
            result.allowsExpensiveNetworkAccess = true
            result.allowsConstrainedNetworkAccess = false
        }
        return result
    }
}

@MainActor
protocol AutomaticModelPreparing {
    func prepare(text: String, allowsCellular: Bool,
                 onProgress: @escaping @MainActor (AutomaticModelDecision, Double?) -> Void) async throws -> AutomaticModelDecision
}

@MainActor
final class LocalAutomaticModelPreparer: AutomaticModelPreparing {
    private let store: LocalModelStore
    private let network: NetworkStatus
    init(store: LocalModelStore, network: NetworkStatus) { self.store = store; self.network = network }
    func prepare(text: String, allowsCellular: Bool,
                 onProgress: @escaping @MainActor (AutomaticModelDecision, Double?) -> Void) async throws -> AutomaticModelDecision {
        try Task.checkCancellation()
        let installed = try await store.installedModels()
        let storage = await store.availableStorageBytes()
        try Task.checkCancellation()
        let environment = AutomaticRouteEnvironment(physicalMemory: ProcessInfo.processInfo.physicalMemory,
            freeStorageBytes: storage, network: network.automaticDownloadNetwork, allowsCellular: allowsCellular)
        let decision = try AutomaticModelRouter.route(text: text, installed: installed, environment: environment)
        onProgress(decision, decision.needsDownload ? 0 : nil)
        if decision.needsDownload {
            try await store.download(decision.model, policy: allowsCellular ? .automaticCellular : .automaticWiFi) { progress in
                Task { @MainActor in onProgress(decision, progress) }
            }
        }
        try Task.checkCancellation()
        // Installed manifests are only a cheap UI check. Hash the actual bytes before readiness.
        _ = try await store.verifiedURL(for: decision.model)
        try Task.checkCancellation()
        return decision
    }
}
