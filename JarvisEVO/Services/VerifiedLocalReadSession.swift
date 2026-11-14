import Foundation
import Observation

@MainActor @Observable
final class VerifiedLocalReadSession {
    private let model: AppModel
    private let core: VerifiedLocalPlanCore
    private let store: LocalAgentStore
    private var raw: String?
    private var work: Task<Void, Never>?
    private(set) var snapshot: VerifiedLocalPlanSnapshot?
    private(set) var records: [VerifiedLocalPlanSnapshot] = []
    private(set) var archivedRecords: [VerifiedLocalPlanSnapshot] = []
    private(set) var archivePage = 0
    private(set) var archivedTotal = 0
    private(set) var report = ""
    private(set) var error: String?
    private var suggestionTask: Task<NativeReadProposal, Error>?
    private(set) var isSuggesting = false
    var isRunning: Bool { work != nil || isSuggesting }
    var canManage: Bool { !isRunning && model.verifiedReadOwner == nil }
    init(model: AppModel, directory: URL) throws {
        self.model = model; core = try VerifiedLocalPlanCore(); store = try LocalAgentStore(directory: directory)
        try reload()
    }
    private func persist(_ state: String) throws {
        let value = try core.snapshot(state)
        try store.save(state, id: value.id)
        raw = state; snapshot = value
        if let index = records.firstIndex(where: { $0.id == value.id }) { records[index] = value }
        else { records.insert(value, at: 0) }
        report = try core.call("report", [state])
    }
    func reload() throws {
        guard canManage else { return }
        // A live shared owner, including another window, is not crashed work.
        var result: [VerifiedLocalPlanSnapshot] = []
        let batch = try store.records()
        var unreadable = batch.unreadable
        for value in batch.values {
            do {
                let recovered = try core.call("recover", [value])
                let item = try core.snapshot(recovered)
                if recovered != value { try store.save(recovered, id: item.id) }
                result.append(item)
            } catch { unreadable += 1 }
        }
        records = result
        let archived = try store.archivedRecords(page: archivePage)
        archivedRecords = archived.values.compactMap { try? core.snapshot($0) }
        archivedTotal = archived.total
        unreadable += archived.unreadable + archived.values.count - archivedRecords.count
        if unreadable > 0 { error = "\(unreadable) saved records could not be loaded. Their files are preserved." }
    }
    func propose(_ text: String) throws -> VerifiedLocalPlanCore.Route {
        guard canManage else { throw LocalAgentError.staleOwner }
        return try core.route(text)
    }
    #if ORIVYN_NATIVE_TOOLS
    func proposeNative(_ text: String) async throws -> NativeReadProposal {
        guard canManage, let provider = model.selectedLocalAgentProvider else { throw LocalAgentError.localModelRequired }
        isSuggesting = true
        let identity = UUID()
        let relay = NativeReadCancellationRelay()
        defer { relay.finish() }
        let task = Task { @MainActor in
            try await model.beginHeavyWork(id: identity, kind: .localAgent)
            withObservationTracking { _ = model.heavyWorkLease } onChange: { relay.cancel() }
            let proposal = try await provider.suggestNativeReads(goal: text) { [model] in
                try Task.checkCancellation()
                guard model.heavyWorkLease?.id == identity, model.heavyWorkLease?.phase == .ready else { throw LocalAgentError.staleOwner }
            }
            try Task.checkCancellation()
            guard model.heavyWorkLease?.id == identity, model.heavyWorkLease?.phase == .ready else { throw LocalAgentError.staleOwner }
            return proposal
        }
        relay.install { task.cancel() }
        suggestionTask = task
        do {
            let proposal = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            relay.finish()
            await model.finishLocalAgentWork(id: identity)
            suggestionTask = nil; isSuggesting = false
            guard !task.isCancelled else { throw CancellationError() }
            try Task.checkCancellation()
            return proposal
        } catch {
            relay.finish()
            await model.finishLocalAgentWork(id: identity)
            suggestionTask = nil; isSuggesting = false
            throw error
        }
    }
    #endif
    func create(appInfo: Bool, installedModels: Bool, searchQuery: String?, memoryQuery: String? = nil) {
        guard canManage else { return }
        do {
            let request = MCPJSONValue.object(["appInfo": .bool(appInfo), "installedModels": .bool(installedModels), "searchQuery": searchQuery.map(MCPJSONValue.string) ?? .null, "memoryQuery": memoryQuery.map(MCPJSONValue.string) ?? .null])
            let data = try request.encoded(maximumBytes: 2048)
            guard let text = String(data: data, encoding: .utf8) else { throw LocalAgentError.invalidState }
            try persist(core.call("create", [text, UUID().uuidString])); error = nil; try reload()
        } catch { self.error = error.localizedDescription }
    }
    func select(id: String) {
        guard canManage else { return }
        do { try persist(core.call("recover", [store.load(id: id)])); error = nil }
        catch { self.error = error.localizedDescription }
    }
    func run() {
        guard canManage, let state = raw, let snapshot, ["ready", "interrupted"].contains(snapshot.status) else { return }
        let owner = UUID()
        guard model.beginVerifiedReads(id: owner) else { return }
        work = Task { @MainActor in
            defer { model.endVerifiedReads(id: owner); work = nil }
            do {
                if snapshot.status == "interrupted" { try persist(core.call("resume", [state])) }
                while let current = raw {
                    try Task.checkCancellation()
                    guard model.verifiedReadOwner == owner else { throw CancellationError() }
                    let item = try core.snapshot(current)
                    guard item.status == "ready" else { break }
                    let next = try core.call("next", [current])
                    try persist(next) // Commit pending identity before reading app state.
                    guard let pending = try core.snapshot(next).pending else { break }
                    let output = try LocalReadTools.execute(name: pending.name, arguments: pending.arguments, model: model)
                    let envelope = try MCPJSONValue.object(["operationID": .string(pending.operationID), "resultJSON": .string(output)]).encoded(maximumBytes: 32_768)
                    guard let result = String(data: envelope, encoding: .utf8) else { throw LocalAgentError.invalidState }
                    try persist(core.call("record", [next, result]))
                    await Task.yield()
                }
                try reload()
            } catch {
                if let current = raw {
                    let method = error is CancellationError ? "recover" : "fail"
                    let args = method == "recover" ? [current] : [current, "The read or result validation failed. No completed report is claimed."]
                    if let failed = try? core.call(method, args) { try? persist(failed) }
                }
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func stop() { work?.cancel(); suggestionTask?.cancel() }
    func changeArchivePage(_ direction: Int) {
        guard canManage else { return }
        let next = archivePage + direction
        guard next >= 0, next * 50 < archivedTotal else { return }
        archivePage = next
        do { try reload() } catch { self.error = error.localizedDescription }
    }
    func restore(id: String) {
        guard canManage else { return }
        do { try store.restore(id: id); archivePage = 0; try reload(); select(id: id) }
        catch { self.error = error.localizedDescription }
    }
    func archive() {
        guard canManage, let id = snapshot?.id else { return }
        do { try store.archive(id: id); snapshot = nil; raw = nil; report = ""; try reload() }
        catch { self.error = error.localizedDescription }
    }
}
