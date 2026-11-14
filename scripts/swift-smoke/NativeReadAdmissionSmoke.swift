import Foundation
import Observation

// Host-only substitutes for Apple JavaScriptCore/persistence/UI state. The files
// under test are the exact production session, provider, relay and engine.
actor LocalModelStore {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var verifying = false
    func verifiedURL(for model: LocalModelDescriptor) async throws -> URL {
        verifying = true
        await withCheckedContinuation { continuation = $0 }
        return URL(fileURLWithPath: "/nonexistent-never-admitted-model.gguf")
    }
    func release() { continuation?.resume(); continuation = nil }
}
struct HostIntent { let name: String; let arguments: MCPJSONValue; let operationID: String }
struct VerifiedLocalPlanSnapshot { let id: String; let status: String; let completed: Int; let pending: HostIntent? }
@MainActor final class VerifiedLocalPlanCore {
    struct Route {}
    func route(_ text: String) throws -> Route { Route() }
    func call(_ method: String, _ args: [String]) throws -> String { throw LocalAgentError.invalidState }
    func snapshot(_ text: String) throws -> VerifiedLocalPlanSnapshot { throw LocalAgentError.invalidState }
}
@MainActor final class LocalAgentStore {
    struct Batch { var values: [String] = []; var unreadable = 0; var total = 0 }
    init(directory: URL) throws {}
    func records() throws -> Batch { Batch() }
    func archivedRecords(page: Int) throws -> Batch { Batch() }
    func save(_ text: String, id: String) throws {}
    func load(id: String) throws -> String { throw LocalAgentError.invalidState }
    func archive(id: String) throws {}
    func restore(id: String) throws {}
}
@MainActor @Observable final class AppModel {
    var verifiedReadOwner: UUID?
    var heavyWorkLease: LocalHeavyWorkLease?
    let selectedLocalAgentProvider: LocalAIProvider?
    init(provider: LocalAIProvider) { selectedLocalAgentProvider = provider }
    func beginHeavyWork(id: UUID, kind: LocalHeavyWorkKind) async throws { heavyWorkLease = LocalHeavyWorkLease(id: id, kind: kind, phase: .ready) }
    func finishLocalAgentWork(id: UUID) async { await selectedLocalAgentProvider?.unload(); if heavyWorkLease?.id == id { heavyWorkLease = nil } }
    func beginVerifiedReads(id: UUID) -> Bool { verifiedReadOwner = id; return true }
    func endVerifiedReads(id: UUID) { verifiedReadOwner = nil }
}
@MainActor enum LocalReadTools {
    static func execute(name: String, arguments: MCPJSONValue, model: AppModel) throws -> String { fatalError("No read may execute during suggestion") }
}
@main struct NativeReadAdmissionSmoke {
    @MainActor static func main() async throws {
        let store = LocalModelStore()
        let descriptor = LocalModelCatalog.recommended.first { $0.sha256 == NativeReadProposal.admittedModelSHA256 }!
        let provider = LocalAIProvider(store: store, model: descriptor)
        let model = AppModel(provider: provider)
        let session = try VerifiedLocalReadSession(model: model, directory: URL(fileURLWithPath: "/unused"))
        let task = Task { try await session.proposeNative("Read the application identity.") }
        while !(await store.verifying) { await Task.yield() }
        guard session.isSuggesting, !session.canManage else { fatalError("Suggestion not owned") }
        // Revoke and complete unload while verification is still deliberately held.
        model.heavyWorkLease?.phase = .revoked
        await provider.unload()
        await store.release()
        do { _ = try await task.value; fatalError("Revoked proposal admitted") }
        catch is CancellationError { print("PASS synchronous revocation cancels during delayed verification; no inference after unload") }
        guard !session.isSuggesting, model.heavyWorkLease == nil else { fatalError("Lease not released") }
        print("PASS production session cleanup and suggestion-only execution boundary")
    }
}
