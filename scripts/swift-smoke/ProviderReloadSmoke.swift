import Foundation
import Glibc

// Explicit descriptor-store/provider/platform doubles. No model load, network,
// keychain, Apple framework, full AppModel or SwiftUI behavior is exercised.
protocol AIProvider {}
actor ControlledModelStore {
    var models: [LocalModelDescriptor] = []
    func set(_ value: [LocalModelDescriptor]) { models = value }
    func installedModels() throws -> [LocalModelDescriptor] { models }
}
struct ControlledEngine {}
struct LocalAIProvider: AIProvider {
    let store: ControlledModelStore
    let model: LocalModelDescriptor
    let engine: ControlledEngine
    func unload() async {}
}
struct SystemModelProvider: AIProvider { static let unavailableReason: String? = "Controlled unavailable platform" }
struct RemoteEndpoint { init(baseURL: String, model: String) throws {} }
struct OpenAICompatibleProvider: AIProvider { init(endpoint: RemoteEndpoint, apiKey: String?) {} }
enum KeychainService { static func read(endpoint: String) throws -> String? { nil } }

@MainActor final class ReloadScaffold {
    let modelStore = ControlledModelStore()
    let localEngine = ControlledEngine()
    var installedModels: [LocalModelDescriptor] = []
    var localProviders: [String: LocalAIProvider] = [:]
    var providers: [ProviderOption] = []
    var selectedProviderID = ""
    var providerRevision = UUID()
    var remoteEnabled = false, remoteBaseURL = "", remoteModelName = ""
    var voiceCancellations = 0, preparationCancellations = 0
    func cancelActiveVoiceTurn() { voiceCancellations += 1 }
    func cancelAutomaticPreparation() { preparationCancellations += 1 }
    // Exact production methods/accessor are inserted by runner, not rewritten here.
    // PRODUCTION_METHODS
}

@main struct ProviderReloadSmoke {
    @MainActor static func main() async throws {
        let model = ReloadScaffold()
        let first = LocalModelDescriptor(id: "same-id", name: "Original", fileName: "first.gguf", downloadURL: nil, sha256: String(repeating: "a", count: 64), byteCount: 123, license: "fixture", sourceURL: nil)
        let changed = LocalModelDescriptor(id: first.id, name: "Replaced", fileName: "replacement.gguf", downloadURL: nil, sha256: String(repeating: "b", count: 64), byteCount: 456, license: "fixture", sourceURL: nil)
        var checks: [[String: Any]] = []
        await model.modelStore.set([first]); try await model.reloadProviders()
        checks.append(["check":"initial descriptor selected", "passed":model.selectedLocalAgentProvider?.model == first])
        await model.modelStore.set([changed]); try await model.reloadProviders()
        checks.append(["check":"same-ID descriptor hash/name/filename refreshed", "passed":model.selectedLocalAgentProvider?.model == changed,
                       "actualName":model.selectedLocalAgentProvider?.model.name ?? "nil", "actualFile":model.selectedLocalAgentProvider?.model.fileName ?? "nil",
                       "actualHash":model.selectedLocalAgentProvider?.model.sha256 ?? "nil", "displayedTitle":model.providers.first?.title ?? "nil"])
        await model.modelStore.set([]); try await model.reloadProviders()
        checks.append(["check":"normal removal selects unavailable fallback", "passed":model.selectedLocalAgentProvider == nil])
        checks.append(["check":"removed descriptor evicted from local provider dictionary", "passed":model.localProviders[first.id] == nil])
        // Explicit stale-selection boundary: a caller retains/restores a removed ID.
        // Normal replaceProviders fallback is tested separately above.
        model.selectedProviderID = first.id
        checks.append(["check":"stale selection cannot expose removed local agent provider", "passed":model.selectedLocalAgentProvider == nil])
        let report: [String: Any] = ["checks":checks,"productionReloadMethodExtractedUnchanged":true,"fullAppModelVerified":false,"nativeIPhoneVerified":false,"modelInferencePerformed":false]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]), as: UTF8.self))
        if checks.contains(where: { $0["passed"] as? Bool != true }) { exit(1) }
    }
}
