import Foundation
import Observation

/// Bounded local read-only agent. No plugin/client/network capability is supplied.
@MainActor @Observable
final class LocalAgentSession {
    typealias DecisionStream = @MainActor (GenerationRequest, any AIProvider) async throws -> AsyncThrowingStream<String, Error>
    private let decisionStream: DecisionStream
    private let model: AppModel
    private let core: LocalAgentCore
    private let store: LocalAgentStore
    private var raw: String?
    private var work: Task<Void, Never>?
    private var owner: UUID?
    private var drafting = false
    private var proposedProviderID: String?
    private var proposedProviderRevision: UUID?
    private var chatContext: ChatLocalTaskContext?
    private var runProviderRevision: UUID?
    func bindConversation(_ context: ChatLocalTaskContext) throws {
        guard !isRunning, snapshot == nil, context.matches(conversationID: model.selectedConversationID,
            conversationRevision: model.pluginResultConversationContext, providerRevision: model.pluginProposalProviderContext) else { throw LocalAgentError.staleOwner }
        chatContext = context
    }
    private func validateChatContext() throws {
        if let context = chatContext {
            guard context.matches(conversationID: model.selectedConversationID,
                conversationRevision: model.pluginResultConversationContext, providerRevision: model.pluginProposalProviderContext),
                model.conversations.contains(where: { $0.id == context.conversationID }) else { throw LocalAgentError.staleOwner }
        }
    }

    private(set) var proposedCompletion: LocalCompletionReview?
    private(set) var proposedReadPlan: LocalReadPlanProposal?
    private(set) var snapshot: LocalAgentSnapshot?
    private(set) var records: [LocalAgentSnapshot] = []
    private(set) var archivedRecords: [LocalAgentSnapshot] = []
    private(set) var archivePage = 0
    private(set) var archivedTotal = 0
    private(set) var status = "Choose a saved task or enter a local read-only task."
    private(set) var error: String?
    private(set) var recoveryWarning: String?
    /// Successful native decisions in the current explicit Run, excluding fallback.
    private(set) var nativeTranscriptDecisionCount = 0
    var isRunning: Bool { work != nil }
    var isPreparingReadPlan: Bool { drafting && isRunning }
    var canManageSavedTasks: Bool { !isRunning && model.heavyWorkLease?.kind != .localAgent }

    init(model: AppModel, directory: URL,
         decisionStream: @escaping DecisionStream = { request, provider in try await provider.stream(request) }) throws {
        self.decisionStream=decisionStream
        self.model = model; core = try LocalAgentCore(); store = try LocalAgentStore(directory: directory)
        try reloadRecords()
    }
    private func persist(_ value: String) throws {
        let item = try core.snapshot(value)
        if let context = chatContext { try store.bindOrigin(id: item.id, conversationID: context.conversationID) }
        try store.save(value, id: item.id)
        raw = value; snapshot = item
        if let index = records.firstIndex(where: { $0.id == item.id }) { records[index] = item }
        else { records.insert(item, at: 0) }
    }
    func reloadRecords() throws {
        guard canManageSavedTasks else { return }
        // A live shared owner, including another window, is not crashed work.
        // Recovery never dispatches work or repeats a pending operation.
        let batch = try store.records()
        var loaded: [LocalAgentSnapshot] = [], failures = batch.unreadable
        for value in batch.values {
            do {
                let recovered = try core.call("recover", [value])
                let item = try core.snapshot(recovered)
                if recovered != value { try store.save(recovered, id: item.id) }
                loaded.append(item)
                if !isRunning, snapshot?.id == item.id { raw = recovered; snapshot = item }
            } catch { failures += 1 }
        }
        records = loaded
        let archived = try store.archivedRecords(page: archivePage)
        archivedTotal = archived.total
        archivedRecords = archived.values.compactMap { try? core.snapshot($0) }
        failures += archived.unreadable + archived.values.count - archivedRecords.count
        recoveryWarning = failures == 0 ? nil : "\(failures) saved task record(s) could not be loaded. Their files were preserved; other tasks remain available."
    }
    func discardReadPlan() {
        guard !isRunning else { return }
        proposedReadPlan = nil; proposedProviderID = nil; proposedProviderRevision = nil; proposedCompletion = nil
    }
    func prepareReadPlan(goal: String, kind: String) {
        guard canManageSavedTasks, proposedCompletion == nil else { return }
        guard let provider = model.selectedLocalAgentProvider else { error = LocalAgentError.localModelRequired.localizedDescription; return }
        let request: GenerationRequest
        do { try validateChatContext(); request = try .readPlanProposal(goal:goal,kind:kind) } catch { self.error=error.localizedDescription; return }
        proposedReadPlan=nil; proposedProviderID=nil
        let identity=UUID(); owner=identity; drafting=true; error=nil
        runProviderRevision = model.pluginProposalProviderContext
        work=Task { @MainActor [self] in
            do {
                try await model.beginHeavyWork(id:identity,kind:.localAgent)
                try checkOwner(identity)
                status="Drafting a read plan locally. No tools run before review."
                var text=""
                for try await part in try await decisionStream(request, provider) {
                    try checkOwner(identity)
                    guard text.utf8.count + part.utf8.count <= 4096 else { throw LocalAgentError.outputBound }
                    text += part
                }
                try checkOwner(identity)
                guard model.selectedLocalAgentProvider?.id == provider.id else { throw LocalAgentError.staleOwner }
                let plan=try LocalReadPlan.parseProposal(text)
                guard plan.kind==kind else { throw LocalAgentError.invalidState }
                proposedReadPlan=LocalReadPlanProposal(goal:goal,plan:plan); proposedProviderID=provider.id; proposedProviderRevision=model.pluginProposalProviderContext
                status="Review the proposed scope. Approval creates a task; Run remains explicit."
            } catch {
                proposedReadPlan=nil; proposedProviderID=nil
                if error is CancellationError { status="Drafting stopped. Saved tasks were preserved." }
                else { self.error=error.localizedDescription; status="Read plan could not be prepared. Saved tasks were preserved." }
            }
            await model.finishLocalAgentWork(id:identity)
            if owner==identity { owner=nil; work=nil; drafting=false }
        }
    }
    func approveReadPlan() {
        guard canManageSavedTasks, let proposal=proposedReadPlan else { return }
        do {
            try validateChatContext()
            guard model.pluginProposalProviderContext == proposedProviderRevision, let selected=model.selectedLocalAgentProvider, selected.id==proposedProviderID else { throw LocalAgentError.staleOwner }
            let planValue=try MCPJSONValue.parse(Data(proposal.plan.encoded().utf8),maximumBytes:4096)
            let request:MCPJSONValue = .object(["goal":.string(proposal.goal),"id":.string(UUID().uuidString),"plan":planValue])
            let state=try core.call("createReviewed",[String(decoding:request.encoded(maximumBytes:4096),as:UTF8.self)])
            try persist(state)
            proposedReadPlan=nil; proposedProviderID=nil; error=nil
            status="Approved read task saved. Tap Run to begin."
            try reloadRecords()
        } catch { self.error=error.localizedDescription }
    }
    func prepareCompletion(goal: String, contract: LocalCompletionContract) {
        guard canManageSavedTasks, proposedReadPlan == nil else { return }
        do {
            try validateChatContext()
            guard let selected=model.selectedLocalAgentProvider else { throw LocalAgentError.localModelRequired }
            proposedProviderRevision=model.pluginProposalProviderContext
            proposedCompletion=try LocalCompletionReview(goal:goal,contract:contract,providerID:selected.id,modelSHA256:selected.model.sha256)
            error=nil; status="Review every exact operation. No local data has been read and no model has run."
        } catch { proposedCompletion=nil; self.error=error.localizedDescription }
    }
    func approveCompletion(goal: String, contract: LocalCompletionContract) {
        guard canManageSavedTasks, proposedReadPlan == nil, let review=proposedCompletion else { return }
        do {
            try validateChatContext()
            guard proposedProviderRevision == model.pluginProposalProviderContext, let selected=model.selectedLocalAgentProvider,
                  try review.matches(goal:goal,contract:contract,providerID:selected.id,modelSHA256:selected.model.sha256) else {
                proposedCompletion=nil; throw LocalAgentError.staleOwner
            }
            let value=try MCPJSONValue.parse(Data(review.contract.encoded().utf8),maximumBytes:4096)
            let request:MCPJSONValue = .object(["goal":.string(review.goal),"id":.string(UUID().uuidString),"contract":value])
            let state=try core.call("createContract",[String(decoding:request.encoded(maximumBytes:4096),as:UTF8.self)])
            try persist(state)
            proposedCompletion=nil; error=nil
            status="Approved checklist saved. Tap Run; no operation starts automatically."
            try reloadRecords()
        } catch { proposedCompletion=nil; self.error=error.localizedDescription }
    }
    func create(goal: String) {
        guard canManageSavedTasks else { return }
        discardReadPlan()
        do {
            try validateChatContext()
            try persist(core.call("create", [goal, UUID().uuidString]))
            error = nil; status = "Ready. Tap Run; no work starts automatically."
            try reloadRecords()
        } catch { self.error = error.localizedDescription }
    }
    func select(id: String) {
        guard canManageSavedTasks else { return }
        discardReadPlan()
        do {
            if let origin = try store.origin(id: id) {
                guard model.selectedConversationID == origin else { throw LocalAgentError.staleOwner }
                if let context = chatContext { guard context.conversationID == origin else { throw LocalAgentError.staleOwner } }
                chatContext = ChatLocalTaskContext(conversationID: origin, conversationRevision: model.pluginResultConversationContext, providerRevision: model.pluginProposalProviderContext)
            } else if chatContext != nil { throw LocalAgentError.staleOwner }
            try validateChatContext()
            try persist(core.call("recover", [store.load(id: id)]))
            error = nil; status = "Loaded saved local task. Resume is explicit."
        } catch { self.error = error.localizedDescription }
    }
    func changeArchivePage(_ direction: Int) {
        guard canManageSavedTasks else { return }
        let next = archivePage + direction
        guard next >= 0, next * 50 < archivedTotal else { return }
        archivePage = next
        do { try reloadRecords() } catch { self.error = error.localizedDescription }
    }
    func archiveSelected() {
        guard canManageSavedTasks, let id = snapshot?.id else { return }
        do {
            try store.archive(id: id)
            raw = nil; snapshot = nil; error = nil
            status = "Task archived without deleting its data. Restore it from Archived tasks."
            try reloadRecords()
        } catch { self.error = error.localizedDescription }
    }
    func restoreArchived(id: String) {
        guard canManageSavedTasks else { return }
        do {
            try store.restore(id: id)
            archivePage = 0
            try reloadRecords()
            select(id: id)
        } catch { self.error = error.localizedDescription }
    }
    func run() {
        guard canManageSavedTasks, proposedReadPlan == nil, proposedCompletion == nil, var state = raw, let current = snapshot,
              ["ready", "interrupted"].contains(current.status) else { return }
        guard let provider = model.selectedLocalAgentProvider else { error = LocalAgentError.localModelRequired.localizedDescription; return }
        do {
            try validateChatContext()
            guard try store.load(id: current.id) == state else { throw LocalAgentError.storage }
            let storedOrigin = try store.origin(id: current.id)
            guard storedOrigin == chatContext?.conversationID else { throw LocalAgentError.staleOwner }
            runProviderRevision = model.pluginProposalProviderContext
            if current.status == "interrupted" { state = try core.call("resume", [state]); try persist(state) }
        } catch { self.error = error.localizedDescription; return }
        nativeTranscriptDecisionCount = 0
        let identity = UUID(); owner = identity; error = nil
        work = Task { @MainActor [self] in
            do {
                try await model.beginHeavyWork(id: identity, kind: .localAgent)
                while true {
                    try checkOwner(identity)
                    guard let value = raw else { throw LocalAgentError.invalidState }
                    let item = try core.snapshot(value)
                    guard item.status == "ready" else { break }
                    status = "Thinking locally · \(item.steps)/6 read-only tool calls used"
                    let prompt = try core.call("prompt", [value])
                    let request: GenerationRequest
                    var nativeFallback:GenerationRequest? = nil
                    if item.version == 3 {
                        guard let contract=item.completionContract else { throw LocalAgentError.invalidState }
                        let policy=try LocalCompletionPolicy.derive(contract:contract,history:item.history)
                        request=GenerationRequest.completionAgent(prompt:prompt,policy:policy)
                    } else if item.version == 2, let plan=item.readPlan {
                        let policy=try LocalReadWorkflowPolicy.derive(plan:plan,history:item.history,conversations:model.conversations)
                        let legacy=GenerationRequest.reviewedAgent(prompt:prompt,policy:policy)
                        #if ORIVYN_NATIVE_TRANSCRIPT
                        if provider.model.sha256.lowercased()==NativeToolTranscript.modelSHA256,
                           let native=try GenerationRequest.reviewedNative(stateJSON:value) {
                            request=native;nativeFallback=legacy
                        } else { request=legacy }
                        #else
                        request=legacy
                        #endif
                    } else if item.version == 1 {
                        let conversationIDs = try JSONDecoder().decode([String].self, from: Data(core.call("conversationIDs", [value]).utf8))
                        request = GenerationRequest.localAgent(prompt: prompt,requiresTool: !item.history.contains { $0.outcome == "succeeded" },conversationIDs:conversationIDs)
                    } else { throw LocalAgentError.invalidState }
                    let decision:String
                    #if ORIVYN_NATIVE_TRANSCRIPT
                    do {
                        decision=try await collectDecision(request,provider:provider,identity:identity)
                        if request.nativeTranscriptInput != nil { nativeTranscriptDecisionCount += 1 }
                    }
                    catch NativeToolTranscript.Failure.wrongTemplate {
                        // No native text is yielded before template validation and
                        // EOG/adapter success. Fall back only for unsupported
                        // template identity, never for malformed model decisions.
                        guard let nativeFallback else { throw NativeToolTranscript.Failure.wrongTemplate }
                        decision=try await collectDecision(nativeFallback,provider:provider,identity:identity)
                    }
                    #else
                    decision=try await collectDecision(request,provider:provider,identity:identity)
                    #endif
                    try checkOwner(identity)
                    let next = try core.call("acceptDecision", [value, decision])
                    let accepted = try core.snapshot(next)
                    if accepted.status == "answered", let plan=item.readPlan {
                        guard try LocalReadWorkflowPolicy.derive(plan:plan,history:item.history,conversations:model.conversations).canAnswer else { throw LocalAgentError.invalidState }
                    }
                    if accepted.status == "answered", item.version == 3 {
                        guard let contract=item.completionContract,
                              try LocalCompletionPolicy.derive(contract:contract,history:item.history).canAnswer else { throw LocalAgentError.invalidState }
                    }
                    try persist(next) // Durable running marker BEFORE any tool reads.
                    if accepted.status == "ready" { continue } // Reducer-only saved-result paging, never a native tool.
                    guard accepted.status == "running", let pending = accepted.pending else { break }
                    status = pending.name == "calculate"
                        ? "Calculating locally · step \(accepted.steps)/6"
                        : "Reading locally: \(pending.name) · step \(accepted.steps)/6"
                    let result = try await executeLocalTool(pending)
                    try checkOwner(identity)
                    let encoded = try MCPJSONValue.object(["operationID": .string(pending.operationID), "result": .string(result)]).encoded(maximumBytes: 32_768)
                    guard let resultText = String(data: encoded, encoding: .utf8) else { throw LocalAgentError.invalidState }
                    try persist(core.call("recordResult", [next, resultText]))
                }
                status = snapshot?.status == "answered" ? "Model answer ready. No external action was performed." : "Task stopped at its safety or step limit."
            } catch {
                if error is CancellationError || (error as? LocalAgentError) == .staleOwner {
                    if let state = raw, let recovered = try? core.call("recover", [state]) { try? persist(recovered) }
                    status = "Local work stopped. No external action was performed."
                } else {
                    self.error = error.localizedDescription
                    // A failed durable write is never followed by another tool.
                    if let state = raw, let failed = try? core.call("fail", [state, "Local task stopped because validation, inference, or storage failed."]) {
                        try? persist(failed)
                    }
                    status = "Task stopped; inspect the error before starting another."
                }
            }
            await model.finishLocalAgentWork(id: identity)
            if owner == identity { owner = nil; work = nil }
            do { try reloadRecords() } catch { self.error = error.localizedDescription }
        }
    }
    private func collectDecision(_ request:GenerationRequest,provider:any AIProvider,identity:UUID) async throws -> String {
        var decision=""
        for try await part in try await decisionStream(request,provider) {
            try checkOwner(identity)
            guard decision.utf8.count+part.utf8.count<=32768 else { throw LocalAgentError.outputBound }
            decision += part
        }
        try checkOwner(identity)
        return decision
    }
    private func checkOwner(_ identity: UUID) throws {
        try Task.checkCancellation()
        try validateChatContext()
        guard runProviderRevision == model.pluginProposalProviderContext else { throw LocalAgentError.staleOwner }
        guard owner == identity, model.heavyWorkLease?.id == identity,
              model.heavyWorkLease?.phase == .ready else { throw LocalAgentError.staleOwner }
    }
    func stop(cancelTask: Bool) {
        if canManageSavedTasks { proposedCompletion=nil }
        guard isRunning || cancelTask && canManageSavedTasks else { return }
        work?.cancel()
        if drafting { proposedReadPlan=nil; proposedProviderID=nil; return }
        guard let state = raw else { return }
        do {
            try persist(core.call(cancelTask ? "cancel" : "recover", [state]))
            status = cancelTask ? "Task canceled. Model resources are being released." : "Paused. Resume is explicit after model resources are released."
        } catch { self.error = error.localizedDescription }
    }

    private func executeLocalTool(_ pending: LocalAgentSnapshot.Intent) async throws -> String {
        guard let snapshot else { throw LocalAgentError.invalidState }
        if snapshot.version == 3 {
            guard let contract=snapshot.completionContract else { throw LocalAgentError.invalidState }
            try LocalCompletionPolicy.derive(contract:contract,history:snapshot.history).validate(pending)
        } else if snapshot.version == 2, let plan=snapshot.readPlan {
            try LocalReadWorkflowPolicy.derive(plan:plan,history:snapshot.history,conversations:model.conversations).validate(pending)
        } else if snapshot.version != 1 { throw LocalAgentError.invalidState }
        // A checklist must carry every prior result in its unchanged 3,500-byte
        // prompt. Reserve room for the contract and subsequent ordinary reads.
        // The shared encoder omits whole capability records with explicit counts;
        // retained prerequisite details are never shortened. Other consumers keep
        // their 4,096-byte budget. Larger cumulative evidence still fails closed.
        let checklistInfoLimit = 1024
        let resultLimit = snapshot.version == 3 && pending.name == "get_app_info" ? checklistInfoLimit : 4096
        return try await LocalReadTools.executeAsync(name: pending.name, arguments: pending.arguments, model: model, resultByteLimit: resultLimit, trustedGoal: snapshot.goal, authorizedConversationIDs: LocalConversationRead.authorizedIDs(history: snapshot.history), reviewedPlan:snapshot.readPlan)
    }

}
