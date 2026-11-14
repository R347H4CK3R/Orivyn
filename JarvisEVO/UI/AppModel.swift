import Foundation
import Observation

struct ProviderOption: Identifiable {
    let id: String
    let title: String
    let detail: String
    let provider: (any AIProvider)?
    var isAvailable: Bool { provider != nil }
}

@MainActor @Observable
final class AppModel {
    private(set) var conversations: [Conversation] = []
    var selectedConversationID: UUID? {
        didSet {
            guard oldValue != selectedConversationID else { return }
            conversationRevision = UUID()
            cancelAutomaticPreparation()
            if let ticket = activeVoiceTurn, selectedConversationID != ticket.conversationID { cancelVoiceTurn(ticket) }
        }
    }
    var draft = "" {
        didSet { if oldValue != draft { composerDidChange() } }
    }
    var pendingAttachments: [ChatAttachment] = [] {
        didSet { if oldValue != pendingAttachments { composerDidChange() } }
    }
    var searchText = ""
    var showArchived = false
    private(set) var isGenerating = false
    private(set) var generatingConversationID: UUID?
    var errorMessage: String?
    var statusMessage: String?
    let network = NetworkStatus()
    private(set) var plugins: PluginBroker?
    private(set) var pluginSetupError: String?
    let workspace: WorkspaceStore
    private(set) var providers: [ProviderOption] = []
    var selectedProviderID: String {
        didSet {
            defaults.set(selectedProviderID, forKey: "selectedProviderID")
            if oldValue != selectedProviderID { providerRevision = UUID(); cancelActiveVoiceTurn(); cancelAutomaticPreparation() }
        }
    }
    var automaticModelsEnabled: Bool {
        didSet {
            defaults.set(automaticModelsEnabled, forKey: "orivyn.automaticModels")
            if oldValue != automaticModelsEnabled { cancelAutomaticPreparation() }
        }
    }
    var automaticAllowsCellular: Bool {
        didSet {
            defaults.set(automaticAllowsCellular, forKey: "orivyn.automaticCellular")
            if oldValue != automaticAllowsCellular { cancelAutomaticPreparation() }
        }
    }
    var conciseQwen3: Bool {
        didSet {
            defaults.set(conciseQwen3, forKey: "orivyn.conciseQwen3")
            if oldValue != conciseQwen3 { cancelActiveVoiceTurn(); cancelAutomaticPreparation() }
        }
    }
    private(set) var automaticDecision: AutomaticModelDecision?
    var isPreparingAutomaticModel: Bool { automaticTicket != nil }
    private(set) var installedModels: [LocalModelDescriptor] = []
    private(set) var memories: [MemoryNote] = []
    private(set) var lastMemoryContextSummary: String?
    private(set) var downloadProgress: Double?
    private(set) var downloadingModelID: String?
    var remoteBaseURL: String
    var remoteModelName: String
    var remoteEnabled: Bool
    private(set) var isLoading = false
    let attachmentService: AttachmentService
    let modelStore: LocalModelStore
    private let store: SQLiteConversationStore
    private let defaults: UserDefaults
    private var generationTask: Task<Result<String, any Error>, Never>?
    private var generationID: UUID?
    private(set) var activeVoiceTurn: VoiceTurnTicket?
    private let voiceContextID = UUID()
    private var conversationRevision = UUID()
    private var providerRevision = UUID()
    private var composerRevision = UUID()
    private var isApplyingOwnedComposerUpdate = false
    private var downloadTask: Task<Void, Never>?
    private var manualDownloadOwner: UUID?
    private var automaticTask: Task<Void, Never>?
    private var automaticTicket: AutomaticPreparationTicket?
    private var automaticDownloadOwner: UUID?
    private var automaticPreparer: (any AutomaticModelPreparing)?
    private var automaticProviderFactory: (@MainActor (LocalModelDescriptor) -> any AIProvider)?
    private let localEngine: LlamaEngine
    private let resourceReleaser: any LocalResourceReleasing
    private(set) var heavyWorkLease: LocalHeavyWorkLease?
    private(set) var localAgentDirectory: URL?
    private(set) var virtualDesktopDirectory: URL?
    private var heavyReleasePending = false
    private var heavyPresenterDismissed = false
    private var heavyWorkForeground = true
    private var thermalBlocksHeavyWork = false
    private var pressureReleaseTask: Task<Void, Never>?
    var isLocalResourceAdmissionBlocked: Bool {
        heavyWorkLease != nil || pressureReleaseTask != nil || thermalBlocksHeavyWork
    }
    var isInferenceAdmissionBlocked: Bool { isLocalResourceAdmissionBlocked || isSavingGeneratedImage }
    var canBeginHeavyWork: Bool {
        !isLocalResourceAdmissionBlocked && heavyWorkForeground && !isGenerating
            && !isPreparingAutomaticModel && !isLoading && !isSavingSubmittedTurn
            && activeVoiceTurn == nil && !isImportingAttachments && !isChangingHistory
            && !isSavingGeneratedImage
    }
    private var localProviders: [String: LocalAIProvider] = [:]
    private let attachmentImporter: any AttachmentImporting
    private var attachmentImportJobs: [UUID: AttachmentImportJob] = [:]
    private var attachmentImportEpoch = UUID()
    private var attachmentCleanupNeeded = false
    private var isChangingHistory = false
    private var isSavingSubmittedTurn = false
    private(set) var generatedImageStager: GeneratedImageStaging?
    private var generatedImageTask: Task<Void, Never>?
    private var generatedImageOperation: UUID?
    private var generatedImageURL: URL?
    private(set) var isSavingGeneratedImageRecord = false
    var isSavingGeneratedImage: Bool { generatedImageTask != nil }

    init(store: SQLiteConversationStore, attachmentService: AttachmentService, modelStore: LocalModelStore,
         providers: [ProviderOption] = [], defaults: UserDefaults = .standard,
         attachmentImporter: (any AttachmentImporting)? = nil,
         automaticPreparer: (any AutomaticModelPreparing)? = nil,
         automaticProviderFactory: (@MainActor (LocalModelDescriptor) -> any AIProvider)? = nil,
         resourceReleaser: (any LocalResourceReleasing)? = nil) {
        let engine = LlamaEngine()
        self.localEngine = engine
        self.resourceReleaser = resourceReleaser ?? engine
        self.store = store
        self.attachmentService = attachmentService
        self.modelStore = modelStore
        self.providers = providers
        self.defaults = defaults
        workspace = WorkspaceStore(defaults: defaults)
        self.attachmentImporter = attachmentImporter ?? LocalAttachmentImporter(service: attachmentService)
        conciseQwen3 = defaults.bool(forKey: "orivyn.conciseQwen3")
        automaticModelsEnabled = defaults.bool(forKey: "orivyn.automaticModels")
        automaticAllowsCellular = defaults.bool(forKey: "orivyn.automaticCellular")
        selectedProviderID = defaults.string(forKey: "selectedProviderID") ?? ""
        remoteBaseURL = defaults.string(forKey: "remoteBaseURL") ?? ""
        remoteModelName = defaults.string(forKey: "remoteModelName") ?? ""
        remoteEnabled = defaults.bool(forKey: "remoteEnabled")
        self.automaticPreparer = automaticPreparer ?? LocalAutomaticModelPreparer(store: modelStore, network: network)
        self.automaticProviderFactory = automaticProviderFactory
        network.onAutomaticPathChange = { [weak self] path in self?.automaticNetworkChanged(to: path) }
    }

    /// Reserve synchronously, then wait for actual text worker/resource cleanup.
    /// The caller supplies the stable presentation identity before the first await.
    func beginHeavyWork(id: UUID, kind: LocalHeavyWorkKind) async throws {
        try Task.checkCancellation()
        guard heavyWorkForeground else { throw LocalHeavyWorkError.background }
        guard !thermalBlocksHeavyWork, pressureReleaseTask == nil else { throw LocalHeavyWorkError.resourcePressure }
        guard canBeginHeavyWork else { throw LocalHeavyWorkError.busy }
        heavyWorkLease = LocalHeavyWorkLease(id: id, kind: kind, phase: .preparing)
        heavyReleasePending = true; heavyPresenterDismissed = false
        await resourceReleaser.unload()
        heavyReleasePending = false
        if heavyPresenterDismissed, heavyWorkLease?.id == id { heavyWorkLease = nil }
        do {
            try Task.checkCancellation()
            guard heavyWorkLease?.id == id, heavyWorkLease?.phase == .preparing,
                  heavyWorkForeground, !thermalBlocksHeavyWork, pressureReleaseTask == nil else {
                throw CancellationError()
            }
            heavyWorkLease?.phase = .ready
        } catch {
            revokeHeavyWork(id: id)
            throw error
        }
    }

    /// Must be called by the outer presentation after dismissal / actual feature cleanup,
    /// never by a nested system sheet's onDisappear. Old owners cannot release new ones.
    func endHeavyWork(id: UUID) {
        guard heavyWorkLease?.id == id else { return }
        heavyPresenterDismissed = true
        if heavyReleasePending { heavyWorkLease?.phase = .revoked }
        else { heavyWorkLease = nil }
    }

    private(set) var verifiedReadOwner: UUID?
    func beginVerifiedReads(id: UUID) -> Bool {
        guard verifiedReadOwner == nil else { return false }
        verifiedReadOwner = id; return true
    }
    func endVerifiedReads(id: UUID) {
        if verifiedReadOwner == id { verifiedReadOwner = nil }
    }

    private(set) var verifiedReadDirectory: URL?
    func configureLocalWork(directory: URL) {
        verifiedReadDirectory = directory.appendingPathComponent("VerifiedLocalTasks", isDirectory: true)
        localAgentDirectory = directory.appendingPathComponent("LocalAgentTasks", isDirectory: true)
        virtualDesktopDirectory = directory.appendingPathComponent("VirtualDesktopCheckpoints", isDirectory: true)
    }

    var selectedLocalAgentProvider: LocalAIProvider? { localProviders[selectedProviderID] }

    /// Agent inference may still be unwinding cancellation. Release the actual
    /// shared engine before dropping this exact lease, never just its view.
    func finishLocalAgentWork(id: UUID) async {
        guard heavyWorkLease?.id == id, heavyWorkLease?.kind == .localAgent else { return }
        revokeHeavyWork(id: id)
        await resourceReleaser.unload()
        endHeavyWork(id: id)
    }

    func revokeHeavyWork(id: UUID? = nil) {
        guard let current = heavyWorkLease, id == nil || id == current.id else { return }
        heavyWorkLease?.phase = .revoked
    }

    func setHeavyWorkForeground(_ foreground: Bool) {
        heavyWorkForeground = foreground
        if !foreground { revokeHeavyWork() }
    }

    func setHeavyWorkThermalState(_ state: ProcessInfo.ThermalState) {
        let blocked = state == .serious || state == .critical
        let newlyBlocked = blocked && !thermalBlocksHeavyWork
        thermalBlocksHeavyWork = blocked
        if newlyBlocked { handleLocalResourcePressure() }
    }

    func handleLocalResourcePressure() {
        revokeHeavyWork()
        stop()
        guard pressureReleaseTask == nil else { return }
        statusMessage = "Memory-intensive work stopped to protect your iPhone. Your draft is kept."
        let releaser = resourceReleaser
        pressureReleaseTask = Task { @MainActor in
            await releaser.unload()
            self.pressureReleaseTask = nil
        }
    }

    func configurePlugins(directory: URL) {
        do { plugins = try PluginBroker(directory: directory); pluginSetupError = nil }
        catch { plugins = nil; pluginSetupError = error.localizedDescription }
    }

    /// Called once before presenting the app, when no accepted image owns a file.
    func configureGeneratedImages(directory: URL) {
        guard generatedImageTask == nil else { return }
        do {
            let staging = try GeneratedImageStaging(directory: directory)
            // Only UUID image files accepted by the stager can be reclaimed.
            for url in try FileManager.default.contentsOfDirectory(at: staging.directory, includingPropertiesForKeys: nil) {
                let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true,
                      UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                      ["png", "jpg", "jpeg", "heic", "heif"].contains(url.pathExtension.lowercased()) else { continue }
                try staging.discard(url)
            }
            generatedImageStager = staging
        } catch { generatedImageStager = nil; report(error) }
    }

    /// Takes cleanup ownership synchronously, before the system image callback returns.
    /// It never submits to a provider or changes the current composer/selection.
    @discardableResult
    func acceptGeneratedImage(_ owned: URL, concept: String, stager: GeneratedImageStaging) -> Task<Void, Never>? {
        guard generatedImageTask == nil, !isChangingHistory, !isLoading,
              !isGenerating, !isPreparingAutomaticModel, !isImportingAttachments,
              ImageCreationAvailability.isValidConcept(concept) else {
            if owned != generatedImageURL { try? stager.discard(owned) }
            errorMessage = "Finish the current image or history operation and use a valid image description."
            return nil
        }
        guard owned.isFileURL, owned.standardizedFileURL.deletingLastPathComponent() == stager.directory,
              UUID(uuidString: owned.deletingPathExtension().lastPathComponent) != nil else {
            errorMessage = "The accepted image is not in Orivyn's private staging storage."
            return nil
        }
        let operation = UUID()
        generatedImageOperation = operation; generatedImageURL = owned
        let importer = attachmentImporter
        let task = Task { @MainActor in
            defer {
                do { try stager.discard(owned) } catch { self.report(error) }
                self.generatedImageOperation = nil; self.generatedImageURL = nil
                self.generatedImageTask = nil; self.isSavingGeneratedImageRecord = false
                self.requestAttachmentCleanup()
            }
            do {
                try Task.checkCancellation()
                let image = try await importer.importAttachment(.file(owned))
                // Importers retain ownership until they return, even after cancellation.
                try Task.checkCancellation()
                guard self.generatedImageOperation == operation, !self.isChangingHistory,
                      image.isImage, self.attachmentService.url(for: image) != nil else {
                    throw CancellationError()
                }
                let conversation = Conversation(title: "Image · " + String(concept.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180)),
                    messages: [ChatMessage(role: .user, content: concept),
                        ChatMessage(role: .assistant, content: "Image created with Apple Image Playground and accepted by you.", attachments: [image])])
                // History mutations wait for this brief atomic save. They may cancel an
                // earlier import, but cannot race a committed result into deleted history.
                self.isSavingGeneratedImageRecord = true
                try await self.store.save(conversation)
                self.upsert(conversation)
            } catch {
                if !(error is CancellationError) { self.report(error) }
            }
        }
        generatedImageTask = task
        return task
    }

    var activeConversation: Conversation? { conversations.first { $0.id == selectedConversationID } }
    var selectedProvider: ProviderOption? { providers.first { $0.id == selectedProviderID } }
    var canSend: Bool { !isInferenceAdmissionBlocked && !isGenerating && !isPreparingAutomaticModel && !isLoading && !isSavingSubmittedTurn && activeVoiceTurn == nil && !isImportingAttachments && !isChangingHistory && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty) }
    var isImportingAttachments: Bool { !attachmentImportJobs.isEmpty }
    var canAcceptIncomingText: Bool {
        !isLocalResourceAdmissionBlocked && !isGenerating && !isPreparingAutomaticModel && !isImportingAttachments && !isLoading && !isChangingHistory
            && !isSavingSubmittedTurn && activeVoiceTurn == nil
    }
    func acceptIncomingText(_ text: String) throws {
        guard canAcceptIncomingText else { throw IncomingTextError.composerBusy }
        // Validate the complete replacement before mutation; preserve attachments and provider.
        let combined = try IncomingTextRequest.appending(text, to: draft)
        draft = combined
    }

    /// Capture before an asynchronous Photos/camera transfer, then pass back to the add method.
    var attachmentImportContext: UUID { attachmentImportEpoch }
    var availableAttachmentSlots: Int {
        guard !isInferenceAdmissionBlocked, !isChangingHistory, !isLoading, !isSavingSubmittedTurn else { return 0 }
        return max(0, 4 - pendingAttachments.count - attachmentImportJobs.values.reduce(0) { $0 + $1.reservedSlots })
    }
    var visibleConversations: [Conversation] {
        conversations.filter { conversation in
            conversation.isArchived == showArchived && ConversationSearch.matches(conversation, query: searchText)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        do {
            conversations = try await store.list(includeArchived: true)
            memories = try await store.memories()
            if selectedConversationID == nil { selectedConversationID = conversations.first(where: { !$0.isArchived })?.id }
            requestAttachmentCleanup()
            try await reloadProviders()
        } catch { report(error) }
    }

    func replaceProviders(_ providers: [ProviderOption]) {
        providerRevision = UUID()
        cancelActiveVoiceTurn()
        cancelAutomaticPreparation()
        self.providers = providers
        if !providers.contains(where: { $0.id == selectedProviderID && $0.isAvailable }) {
            selectedProviderID = providers.first(where: \.isAvailable)?.id ?? providers.first?.id ?? ""
        }
    }

    func reloadProviders() async throws {
        installedModels = try await modelStore.installedModels()
        var options: [ProviderOption] = []
        var refreshedLocalProviders: [String: LocalAIProvider] = [:]
        for model in installedModels {
            let provider: LocalAIProvider
            if let existing = localProviders[model.id], existing.model == model { provider = existing }
            else { provider = LocalAIProvider(store: modelStore, model: model, engine: localEngine) }
            refreshedLocalProviders[model.id] = provider
            options.append(ProviderOption(id: model.id, title: model.name, detail: "On this iPhone · works offline", provider: provider))
        }
        if options.isEmpty {
            options.append(ProviderOption(id: "local-unavailable", title: "Local model", detail: "Download or import a model to start chatting offline.", provider: nil))
        }
        let systemReason = SystemModelProvider.unavailableReason
        options.append(ProviderOption(id: "apple-system", title: "Apple on-device model",
                                      detail: systemReason ?? "Optional system model · works on device",
                                      provider: systemReason == nil ? SystemModelProvider() : nil))
        if remoteEnabled && !remoteBaseURL.isEmpty && !remoteModelName.isEmpty {
            let endpoint = try RemoteEndpoint(baseURL: remoteBaseURL, model: remoteModelName)
            let provider = OpenAICompatibleProvider(endpoint: endpoint, apiKey: try KeychainService.read(endpoint: remoteBaseURL))
            options.append(ProviderOption(id: "remote", title: remoteModelName, detail: "Remote · sends conversation and extracted attachment text to your endpoint", provider: provider))
        }
        // Publish only the current installed descriptors; do not retain removed IDs
        // or an old hash/path behind an updated display name. The shared runtime stays owned.
        localProviders = refreshedLocalProviders
        replaceProviders(options)
    }

    func selectConversation(_ id: UUID) {
        selectedConversationID = id
        draft = ""
        clearPendingAttachments()
    }

    @discardableResult
    func newConversation() async -> Bool {
        guard beginHistoryChange() else { return false }
        defer { finishHistoryChange() }
        cancelActiveVoiceTurn()
        cancelAttachmentImports()
        do {
            let conversation = Conversation(id: UUID(), title: "New conversation", createdAt: Date(), updatedAt: Date(), isArchived: false, messages: [])
            try await store.save(conversation)
            conversations.insert(conversation, at: 0)
            selectConversation(conversation.id)
            showArchived = false
            searchText = ""
            return true
        } catch { report(error); return false }
    }

    /// Safe preflight: does not create a chat or change the composer. The UI may
    /// call this before enabling the microphone and discard that preflight ticket.
    /// Create a fresh ticket for each final transcript, immediately before sendVoice.
    func makeVoiceTurnTicket(ownerID: UUID) throws -> VoiceTurnTicket {
        try Task.checkCancellation()
        try validateVoiceAvailability()
        return VoiceTurnTicket(ownerID: ownerID, modelID: voiceContextID,
                               conversationID: selectedConversationID ?? UUID(),
                               originatingConversationID: selectedConversationID, providerID: selectedProviderID,
                               conversationRevision: conversationRevision, providerRevision: providerRevision,
                               composerContext: attachmentImportEpoch, composerRevision: composerRevision, draft: draft)
    }

    /// Returns only this ticket's complete, nonempty, durably saved assistant text.
    /// The controller must await this call, never return immediately after send().
    func sendVoice(_ text: String, ticket: VoiceTurnTicket) async throws -> String {
        try Task.checkCancellation()
        guard ticket.modelID == voiceContextID, !ticket.wasSubmitted else { throw VoiceTurnError.invalidTicket }
        guard !ticket.isCancelled else { throw CancellationError() }
        guard ticket.originatingConversationID == selectedConversationID,
              ticket.conversationRevision == conversationRevision, ticket.providerRevision == providerRevision,
              ticket.providerID == selectedProviderID, ticket.composerContext == attachmentImportEpoch,
              ticket.composerRevision == composerRevision, ticket.draft == draft else { throw VoiceTurnError.contextChanged }
        try validateVoiceAvailability()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConversationError.emptyMessage }
        guard let provider = selectedProvider?.provider else { throw ProviderError.notConfigured }
        ticket.wasSubmitted = true
        // Bind ownership before selecting a newly created chat. UI selection
        // observers can recognize this as our own transition, not a user switch.
        activeVoiceTurn = ticket
        let task = submit(text: text, attachments: [], conversationID: ticket.conversationID,
                          provider: provider, providerID: ticket.providerID, voiceTicket: ticket)
        return try await withTaskCancellationHandler {
            let result = await task.value
            try Task.checkCancellation()
            // Preserve provider/storage errors, including failed final persistence,
            // before checking whether a successful result still belongs in voice.
            let response = try result.get()
            try self.validateVoiceContext(ticket)
            return response
        } onCancel: {
            // Capturing this exact task avoids a delayed cancellation targeting a
            // later manual or voice generation after the original has completed.
            task.cancel()
        }
    }

    /// Latches even before sendVoice starts. Retired/foreign tickets can never
    /// cancel another owner's or a later generation's work.
    func cancelVoiceTurn(_ ticket: VoiceTurnTicket) {
        guard ticket.modelID == voiceContextID else { return }
        ticket.isCancelled = true
        guard activeVoiceTurn === ticket, generationID == ticket.id else { return }
        generationTask?.cancel()
    }

    private func cancelActiveVoiceTurn() {
        if let ticket = activeVoiceTurn { cancelVoiceTurn(ticket) }
    }

    private func validateVoiceAvailability() throws {
        guard pendingAttachments.isEmpty, !isImportingAttachments else { throw VoiceTurnError.attachmentsPending }
        guard !isInferenceAdmissionBlocked, !isGenerating, !isPreparingAutomaticModel, !isLoading, !isChangingHistory, !isSavingSubmittedTurn else { throw VoiceTurnError.busy }
        guard selectedProvider?.provider != nil else { throw ProviderError.notConfigured }
        if selectedProviderID == "remote", network.isOnline == false { throw VoiceTurnError.offlineRemote }
    }

    private func validateVoiceContext(_ ticket: VoiceTurnTicket) throws {
        guard !ticket.isCancelled else { throw CancellationError() }
        guard selectedConversationID == ticket.conversationID,
              conversationRevision == ticket.acceptedConversationRevision,
              selectedProviderID == ticket.providerID, providerRevision == ticket.providerRevision,
              attachmentImportEpoch == ticket.acceptedComposerContext, composerRevision == ticket.composerRevision,
              draft.isEmpty, pendingAttachments.isEmpty, !isImportingAttachments else {
            throw VoiceTurnError.contextChanged
        }
    }

    /// Latch external edits, even when text/files later return to the old value.
    /// Cancelling voice never cancels the unrelated import or changes its files.
    private func composerDidChange() {
        guard !isApplyingOwnedComposerUpdate else { return }
        composerRevision = UUID()
        cancelActiveVoiceTurn()
        cancelAutomaticPreparation()
    }

    private func applyingOwnedComposerUpdate(_ update: () -> Void) {
        let wasApplying = isApplyingOwnedComposerUpdate
        isApplyingOwnedComposerUpdate = true
        defer { isApplyingOwnedComposerUpdate = wasApplying }
        update()
    }

    private func validateGeneration(_ ticket: VoiceTurnTicket?) throws {
        try Task.checkCancellation()
        guard !isInferenceAdmissionBlocked else { throw LocalHeavyWorkError.busy }
        if let ticket { try validateVoiceContext(ticket) }
    }

    func send() {
        guard canSend else { return }
        if automaticModelsEnabled { prepareAutomaticSend(); return }
        if selectedProviderID == "remote" && network.isOnline == false {
            guard let local = providers.first(where: { $0.id != "remote" && $0.isAvailable }) else {
                errorMessage = "You’re offline and no local model is ready. Your draft is saved in the composer. Install a local model when connected to chat offline."
                return
            }
            selectedProviderID = local.id
            statusMessage = "You’re offline. Switched to \(local.title) on this iPhone."
        }
        guard let provider = selectedProvider?.provider else {
            errorMessage = "No model is ready yet. Open Models to download or import a local model, or configure your own remote endpoint in Settings."
            return
        }
        submit(text: draft, attachments: pendingAttachments, conversationID: selectedConversationID ?? UUID(), provider: provider, providerID: selectedProviderID)
    }

    private func prepareAutomaticSend() {
        guard downloadTask == nil, let preparer = automaticPreparer else {
            errorMessage = "A model download is already running. Your draft is unchanged; finish or cancel it before Automatic can prepare this request."
            return
        }
        let ticket = AutomaticPreparationTicket(conversationID: selectedConversationID,
            conversationRevision: conversationRevision, providerRevision: providerRevision,
            composerRevision: composerRevision, draft: draft, attachments: pendingAttachments.map(\.id))
        automaticTicket = ticket
        automaticDecision = nil
        errorMessage = nil
        automaticTask = Task { [weak self] in
            guard let self else { return }
            do {
                let decision = try await preparer.prepare(text: ticket.draft, allowsCellular: self.automaticAllowsCellular) { [weak self] decision, fraction in
                    guard let self, self.ownsAutomatic(ticket) else { return }
                    self.automaticDecision = decision
                    if decision.needsDownload {
                        self.automaticDownloadOwner = ticket.id
                        self.downloadingModelID = decision.model.id
                        self.downloadProgress = fraction
                    }
                }
                try Task.checkCancellation()
                guard self.ownsAutomatic(ticket) else { return }
                let provider: any AIProvider
                if let factory = self.automaticProviderFactory { provider = factory(decision.model) }
                else {
                    let local = self.localProviders[decision.model.id].flatMap { $0.model == decision.model ? $0 : nil }
                        ?? LocalAIProvider(store: self.modelStore, model: decision.model, engine: self.localEngine)
                    self.localProviders[decision.model.id] = local
                    provider = local
                }
                // No await from the final ownership check through submission. The manual
                // provider preference remains unchanged; this provider belongs to one turn.
                self.installedModels.removeAll { $0.id == decision.model.id }
                self.installedModels.append(decision.model)
                self.providers.removeAll { $0.id == decision.model.id || $0.id == "local-unavailable" }
                self.providers.append(ProviderOption(id: decision.model.id, title: decision.model.name,
                    detail: "On this iPhone · works offline", provider: provider))
                self.clearAutomaticOwnership(ticket.id)
                self.automaticDecision = decision
                self.statusMessage = "Automatic: \(decision.model.name) · \(decision.purpose) · on this iPhone"
                self.submit(text: self.draft, attachments: self.pendingAttachments,
                    conversationID: self.selectedConversationID ?? UUID(), provider: provider, providerID: decision.model.id)
            } catch {
                guard self.automaticTicket?.id == ticket.id else { return }
                self.clearAutomaticOwnership(ticket.id)
                if !(error is CancellationError) && !Task.isCancelled {
                    self.errorMessage = "Automatic preparation stopped: \(error.localizedDescription) Your draft is unchanged. You can choose a model manually."
                }
            }
        }
    }

    private func ownsAutomatic(_ ticket: AutomaticPreparationTicket) -> Bool {
        automaticTicket?.id == ticket.id && automaticModelsEnabled
            && ticket.conversationID == selectedConversationID && ticket.conversationRevision == conversationRevision
            && ticket.providerRevision == providerRevision && ticket.composerRevision == composerRevision
            && ticket.draft == draft && ticket.attachments == pendingAttachments.map(\.id)
            && !isGenerating && !isImportingAttachments && !isChangingHistory && !isLoading
            && !isSavingSubmittedTurn && activeVoiceTurn == nil
    }
    private func clearAutomaticOwnership(_ id: UUID) {
        guard automaticTicket?.id == id else { return }
        automaticTicket = nil
        automaticTask = nil
        if automaticDownloadOwner == id {
            automaticDownloadOwner = nil; downloadingModelID = nil; downloadProgress = nil
        }
    }
    func automaticNetworkChanged(to path: AutomaticDownloadNetwork) {
        // Path monitoring is best-effort across transitions. URLSession additionally
        // enforces cellular/expensive flags and always forbids Low Data Mode for auto.
        guard automaticDownloadOwner != nil else { return }
        let permitted = path == .wifi || path == .wired || (path == .cellular && automaticAllowsCellular)
        if !permitted {
            cancelAutomaticPreparation()
            statusMessage = "Automatic download paused because the connection no longer meets your policy. Your draft is unchanged; send again when ready."
        }
    }
    func cancelAutomaticPreparation() {
        guard let id = automaticTicket?.id else { return }
        let task = automaticTask
        clearAutomaticOwnership(id)
        automaticDecision = nil
        task?.cancel()
    }

    @discardableResult
    private func submit(text: String, attachments: [ChatAttachment], conversationID: UUID, provider: any AIProvider, providerID: String,
                        voiceTicket: VoiceTurnTicket? = nil) -> Task<Result<String, any Error>, Never> {
        guard !isInferenceAdmissionBlocked else { return Task { .failure(LocalHeavyWorkError.busy) } }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = ChatMessage(id: UUID(), role: .user, content: content.isEmpty ? "Please review the attached file." : content,
                                  createdAt: Date(), state: .complete, attachments: attachments)
        var conversation = activeConversation ?? Conversation(id: conversationID, title: "New conversation", createdAt: Date(), updatedAt: Date(), isArchived: false, messages: [])
        conversation.messages.append(message)
        conversation.isArchived = false
        if conversation.title == "New conversation" { conversation.title = String(message.content.prefix(60)) }
        conversation.updatedAt = Date()
        selectedConversationID = conversation.id
        voiceTicket?.acceptedConversationRevision = conversationRevision
        let assistant = ChatMessage(id: UUID(), role: .assistant, content: "", createdAt: Date(), state: .streaming, attachments: [])
        conversation.messages.append(assistant)
        upsert(conversation)
        applyingOwnedComposerUpdate {
            draft = ""
            pendingAttachments = []
            // A Photos transfer started for this draft must not attach itself to the next draft after Send.
            cancelAttachmentImports()
        }
        voiceTicket?.acceptedComposerContext = attachmentImportEpoch
        return startGeneration(conversationID: conversation.id, assistantID: assistant.id, provider: provider, providerID: providerID,
                               restoringDraftOnSaveFailure: message, voiceTicket: voiceTicket)
    }

    @discardableResult
    private func startGeneration(conversationID: UUID, assistantID: UUID, provider: any AIProvider, providerID: String,
                                 restoringDraftOnSaveFailure original: ChatMessage? = nil,
                                 voiceTicket: VoiceTurnTicket? = nil) -> Task<Result<String, any Error>, Never> {
        guard !isInferenceAdmissionBlocked else { return Task { .failure(LocalHeavyWorkError.busy) } }
        // Capture the actual turn provider, not a picker preference that Automatic preserves
        // or that can change while the initial save is suspended.
        let generation = voiceTicket?.id ?? UUID()
        generationID = generation
        isGenerating = true
        generatingConversationID = conversationID
        isSavingSubmittedTurn = original != nil
        let composerContext = attachmentImportEpoch
        let task = Task { [weak self] () -> Result<String, any Error> in
            guard let self else { return .failure(CancellationError()) }
            defer {
                if self.generationID == generation {
                    self.isSavingSubmittedTurn = false
                    self.isGenerating = false
                    self.generatingConversationID = nil
                    self.generationTask = nil
                    self.generationID = nil
                    if self.activeVoiceTurn?.id == generation { self.activeVoiceTurn = nil }
                }
            }
            var didPersist = false
            do {
                try self.validateGeneration(voiceTicket)
                guard let conversation = self.conversations.first(where: { $0.id == conversationID }) else {
                    throw ConversationError.messageNotFound
                }
                try await self.store.save(conversation)
                didPersist = true
                self.isSavingSubmittedTurn = false
                try self.validateGeneration(voiceTicket)
                let memoryContext = MemoryContextBuilder.build(
                    notes: self.memories,
                    query: conversation.messages.last(where: { $0.role == .user })?.content ?? "",
                    maximumBytes: providerID == "remote" ? 1024 : 512)
                self.lastMemoryContextSummary = memoryContext.totalCount == 0 ? nil :
                    "Latest prepared context selected \(memoryContext.includedCount) of \(memoryContext.totalCount) saved notes; scanned \(memoryContext.scannedCount)."
                    + (memoryContext.truncated ? " Some context was omitted or shortened; all original notes remain saved." : "")

                let system = "You are Jarvis, the assistant in Orivyn. Do the useful parts of the request first: explain, draft, analyze or provide concrete steps. When an action needs a device tool, suggest review in the real Email, Calendar, Calculator, Browser, Location or Reminder screen. Opening a review does not send, save or execute it. Be clear about uncertainty and limitations. Do not claim to browse, run code, or take actions that you cannot perform. All configured providers receive text only. Image attachments supply OCR text, never image pixels. Do not infer objects, people, colors, layout, or other visual contents from an image attachment. " + AppSelfKnowledge.prompt(providerID: providerID) + "\n" + self.workspace.behavior.prompt + (memoryContext.text.isEmpty ? "" : "\n" + memoryContext.text)
                let request = GenerationRequest(messages: Array(conversation.messages.dropLast()), systemPrompt: system, maxTokens: 1024, temperature: 0.7, conciseQwen3: self.conciseQwen3)
                let stream = try await provider.stream(request)
                var checkpoint = Date()
                for try await token in stream {
                    try self.validateGeneration(voiceTicket)
                    self.updateMessage(conversationID: conversationID, messageID: assistantID) { $0.content += token }
                    if Date().timeIntervalSince(checkpoint) >= 0.25 {
                        try await self.persist(conversationID)
                        checkpoint = Date()
                    }
                }
                try self.validateGeneration(voiceTicket)
                guard let answer = self.conversations.first(where: { $0.id == conversationID })?.messages.first(where: { $0.id == assistantID })?.content else {
                    throw ConversationError.messageNotFound
                }
                guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProviderError.emptyResponse }
                self.updateMessage(conversationID: conversationID, messageID: assistantID) { $0.state = .complete }
                try await self.persist(conversationID)
                try self.validateGeneration(voiceTicket)
                return .success(answer)
            } catch {
                self.updateMessage(conversationID: conversationID, messageID: assistantID) { message in
                    message.state = Task.isCancelled || error is CancellationError ? .interrupted : .failed
                }
                if didPersist { try? await self.persist(conversationID) }
                if !didPersist, let original {
                    if self.selectedConversationID == conversationID, self.attachmentImportEpoch == composerContext,
                       self.draft.isEmpty, self.pendingAttachments.isEmpty, self.attachmentImportJobs.isEmpty {
                        self.applyingOwnedComposerUpdate {
                            self.draft = original.content
                            self.pendingAttachments = original.attachments
                        }
                        if let index = self.conversations.firstIndex(where: { $0.id == conversationID }) {
                            self.conversations[index].messages.removeAll { $0.id == original.id || $0.id == assistantID }
                        }
                    } else {
                        // Keep the failed user turn and its files in the originating conversation rather
                        // than overwriting a different draft. It is not durable until a later save succeeds.
                        self.statusMessage = "The unsaved message is still in its original conversation. Return there to edit or copy it before closing the app."
                    }
                    self.requestAttachmentCleanup()
                }
                if !Task.isCancelled && !(error is CancellationError) { self.report(error) }
                return .failure(error)
            }
        }
        generationTask = task
        return task
    }

    func stop() { cancelAutomaticPreparation(); cancelActiveVoiceTurn(); generationTask?.cancel() }

    @discardableResult
    func rename(_ id: UUID, to title: String) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isLoading,
              var proposed = conversations.first(where: { $0.id == id }) else { return false }
        guard generatingConversationID != id else {
            errorMessage = "Wait for this conversation's response to finish before renaming it."
            return false
        }
        guard beginHistoryChange() else { return false }
        defer { finishHistoryChange() }
        proposed.title = String(title.prefix(200))
        proposed.updatedAt = Date()
        do {
            try await store.save(proposed)
            if let index = conversations.firstIndex(where: { $0.id == id }) {
                // Do not replace live message state with an earlier metadata-edit snapshot.
                conversations[index].title = proposed.title
                conversations[index].updatedAt = proposed.updatedAt
            }
            return true
        } catch { report(error); return false }
    }

    @discardableResult
    func archive(_ id: UUID, archived: Bool) async -> Bool {
        guard !isLoading, var proposed = conversations.first(where: { $0.id == id }) else { return false }
        guard generatingConversationID != id else {
            errorMessage = "Wait for this conversation's response to finish before changing its archive status."
            return false
        }
        guard beginHistoryChange() else { return false }
        defer { finishHistoryChange() }
        proposed.isArchived = archived
        proposed.updatedAt = Date()
        do {
            try await store.save(proposed)
            if let index = conversations.firstIndex(where: { $0.id == id }) {
                conversations[index].isArchived = proposed.isArchived
                conversations[index].updatedAt = proposed.updatedAt
            }
            return true
        } catch { report(error); return false }
    }

    func delete(_ id: UUID) async {
        guard beginHistoryChange() else { return }
        defer { finishHistoryChange() }
        if selectedConversationID == id { cancelAttachmentImports() }
        if generatingConversationID == id { stop(); _ = await generationTask?.value }
        do {
            try await store.delete(id: id)
            conversations.removeAll { $0.id == id }
            if selectedConversationID == id {
                selectedConversationID = nil
                draft = ""
                clearPendingAttachments()
            }
            requestAttachmentCleanup()
        } catch { report(error) }
    }

    func deleteAllContent() async {
        guard beginHistoryChange() else { return }
        defer { finishHistoryChange() }
        cancelAttachmentImports()
        stop()
        _ = await generationTask?.value
        do {
            let maintenanceWarning = try await store.deleteAll()
            statusMessage = maintenanceWarning
            conversations = []
            memories = []
            selectedConversationID = nil
            draft = ""
            pendingAttachments = []
            requestAttachmentCleanup()
        } catch { report(error) }
    }

    @discardableResult
    func branch(through messageID: UUID, sourceConversationID: UUID? = nil) async -> Bool {
        guard !isInferenceAdmissionBlocked, !isGenerating, let activeConversation,
              sourceConversationID == nil || sourceConversationID == activeConversation.id else { return false }
        guard beginHistoryChange() else { return false }
        defer { finishHistoryChange() }
        cancelAttachmentImports()
        do {
            let branched = try activeConversation.branching(through: messageID)
            try await store.save(branched)
            upsert(branched)
            if selectedConversationID == activeConversation.id { selectedConversationID = branched.id }
            else { statusMessage = "The branch was saved without changing your current conversation." }
            return true
        } catch { report(error); return false }
    }

    @discardableResult
    func editAndBranch(messageID: UUID, text: String, sourceConversationID: UUID? = nil) async -> Bool {
        guard !isInferenceAdmissionBlocked, !isGenerating, let original = activeConversation else { return false }
        guard sourceConversationID == nil || sourceConversationID == original.id else {
            errorMessage = "The conversation changed. Your edit is kept; return to its original conversation before saving."
            return false
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 1_000_000 else { return false }
        guard let provider = selectedProvider?.provider else { errorMessage = "Choose an available model before saving and sending the edit."; return false }
        let providerIdentity = providerRevision
        let providerID = selectedProviderID
        guard beginHistoryChange() else { return false }
        defer { finishHistoryChange() }
        cancelAttachmentImports()
        do {
            var branched = try original.branching(through: messageID)
            guard let last = branched.messages.last, last.role == .user else { return false }
            try branched.editUserMessage(id: last.id, content: text)
            try await store.save(branched)
            upsert(branched)
            guard selectedConversationID == original.id, providerRevision == providerIdentity else {
                statusMessage = "Your edited branch was saved. No response started because the conversation or model changed."
                return true
            }
            selectedConversationID = branched.id // Preserve the unrelated composer draft and attachments.
            regenerateLastUserTurn(in: branched.id, provider: provider, providerID: providerID)
            return true
        } catch { report(error); return false }
    }

    @discardableResult
    func regenerate(messageID: UUID, sourceConversationID: UUID? = nil) async -> Bool {
        guard !isInferenceAdmissionBlocked, !isGenerating, let original = activeConversation,
              sourceConversationID == nil || sourceConversationID == original.id,
              let index = original.messages.firstIndex(where: { $0.id == messageID }),
              original.messages[index].role == .assistant,
              let user = original.messages[..<index].last(where: { $0.role == .user }) else { return false }
        guard let provider = selectedProvider?.provider else { errorMessage = "Choose an available model before regenerating."; return false }
        let providerIdentity = providerRevision
        let providerID = selectedProviderID
        guard beginHistoryChange() else { return false }
        defer { finishHistoryChange() }
        cancelAttachmentImports()
        do {
            let branched = try original.branching(through: user.id)
            try await store.save(branched)
            upsert(branched)
            guard selectedConversationID == original.id, providerRevision == providerIdentity else {
                statusMessage = "The new branch was saved. No response started because the conversation or model changed."
                return true
            }
            selectedConversationID = branched.id
            regenerateLastUserTurn(in: branched.id, provider: provider, providerID: providerID)
            return true
        } catch { report(error); return false }
    }

    private func regenerateLastUserTurn(in conversationID: UUID, provider: any AIProvider, providerID: String) {
        guard !isInferenceAdmissionBlocked, !isGenerating, selectedConversationID == conversationID,
              var conversation = activeConversation, conversation.messages.last?.role == .user else {
            statusMessage = "The branch is saved, but the response could not start in its original context."
            return
        }
        let assistant = ChatMessage(id: UUID(), role: .assistant, content: "", createdAt: Date(), state: .streaming, attachments: [])
        conversation.messages.append(assistant)
        upsert(conversation)
        startGeneration(conversationID: conversation.id, assistantID: assistant.id, provider: provider, providerID: providerID)
    }

    func addAttachments(from urls: [URL], context: UUID? = nil) async {
        await addAttachmentSources(urls.map(AttachmentImportSource.file), context: context)
    }

    func addImageAttachment(data: Data, suggestedName: String, context: UUID? = nil) async {
        await addAttachmentSources([.image(data: data, suggestedName: suggestedName)], context: context)
    }

    func cancelAttachmentImports() {
        composerDidChange()
        attachmentImportEpoch = UUID()
        for job in attachmentImportJobs.values { job.task.cancel() }
        // Keep reservations until completion: cancelled Vision work may still be finishing off-main.
    }

    private func addAttachmentSources(_ sources: [AttachmentImportSource], context: UUID?) async {
        guard !Task.isCancelled, !sources.isEmpty, context == nil || context == attachmentImportEpoch else { return }
        guard !isChangingHistory, !isLoading else { errorMessage = "Wait for the history operation to finish before attaching files."; return }
        guard !isSavingSubmittedTurn else { errorMessage = "Wait for the sent message to be saved before attaching more files."; return }
        guard sources.count <= availableAttachmentSlots else { errorMessage = "Attach up to four files per message, including files still importing."; return }
        composerDidChange()
        let epoch = attachmentImportEpoch
        let conversationID = selectedConversationID
        let jobID = UUID()
        let importer = attachmentImporter
        let task = Task<AttachmentImportOutcome, Never> {
            var imported: [ChatAttachment] = []
            do {
                for source in sources {
                    try Task.checkCancellation()
                    imported.append(try await importer.importAttachment(source))
                    // Record ownership before observing cancellation, so late successes are cleaned up.
                    try Task.checkCancellation()
                }
                return AttachmentImportOutcome(attachments: imported, errorMessage: nil, wasCancelled: false)
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                return AttachmentImportOutcome(attachments: imported, errorMessage: cancelled ? nil : error.localizedDescription,
                                               wasCancelled: cancelled)
            }
        }
        // The main actor reserves the entire batch before another call can inspect available slots.
        cancelAutomaticPreparation()
        attachmentImportJobs[jobID] = AttachmentImportJob(reservedSlots: sources.count, task: task)
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        attachmentImportJobs.removeValue(forKey: jobID)
        if epoch == attachmentImportEpoch, conversationID == selectedConversationID,
           !Task.isCancelled, !task.isCancelled, !result.wasCancelled {
            pendingAttachments.append(contentsOf: result.attachments)
            if let message = result.errorMessage { errorMessage = message }
        }
        // Current results are now referenced; stale/cancelled results are not. Sweep only after every
        // importer has handed back its files, never while another importer is writing an unseen file.
        requestAttachmentCleanup()
    }

    func removePendingAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
        requestAttachmentCleanup()
    }

    func clearPendingAttachments() {
        cancelAttachmentImports()
        pendingAttachments = []
        requestAttachmentCleanup()
    }

    var runtimeDiagnosticState: RuntimeDiagnosticState {
        var state = RuntimeDiagnosticState()
        state.generating = isGenerating
        if let id = generatingConversationID,
           let conversation = conversations.first(where: { $0.id == id }),
           let response = conversation.messages.last, response.role == .assistant {
            state.generatedCharacters = response.content.count
        }
        state.preparingModel = isPreparingAutomaticModel
        if downloadingModelID != nil, let progress = downloadProgress, progress.isFinite {
            state.downloadPercent = Int(min(1, max(0, progress)) * 100)
        }
        state.importingAttachments = isImportingAttachments
        state.savingImage = isSavingGeneratedImage
        state.admissionBlocked = isInferenceAdmissionBlocked
        state.online = network.isOnline
        state.installedModelCount = installedModels.count
        if let lease = heavyWorkLease {
            switch lease.kind {
            case .imageCreation: state.heavyWork = "Image creation"
            case .vision: state.heavyWork = "Vision"
            case .virtualDesktop: state.heavyWork = "Virtual desktop"
            case .localAgent: state.heavyWork = "Local agent"
            }
            switch lease.phase {
            case .preparing: state.heavyPhase = "Preparing"
            case .ready: state.heavyPhase = "Ready (not proof of progress)"
            case .revoked: state.heavyPhase = "Revoked; teardown pending"
            }
        }
        state.hasReportedError = errorMessage != nil
        return state
    }

    func exportData() async throws -> Data { try await store.exportData() }

    func importHistory(from url: URL, policy: BackupImportPolicy = .preserveLocal) async {
        guard !isGenerating else { errorMessage = "Stop the current response before importing history."; return }
        guard beginHistoryChange() else { return }
        defer { finishHistoryChange() }
        cancelAttachmentImports()
        do {
            let data = try await BackupFileReader.read(url)
            try Task.checkCancellation()
            let summary = try await store.importData(data, policy: policy)
            conversations = try await store.list(includeArchived: true)
            memories = try await store.memories()
            statusMessage = summary.description
            requestAttachmentCleanup()
        } catch { report(error) }
    }

    @discardableResult
    func saveMemory(id: UUID? = nil, content: String) async -> Bool {
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.count <= 4_000, content.utf8.count <= 32_768 else { return false }
        do {
            let existing = memories.first(where: { $0.id == id })
            try await store.saveMemory(MemoryNote(id: id ?? UUID(), content: content, createdAt: existing?.createdAt ?? Date()))
            memories = try await store.memories()
            return true
        } catch { report(error); return false }
    }

    func deleteMemory(_ id: UUID) async {
        do { try await store.deleteMemory(id: id); memories = try await store.memories() }
        catch { report(error) }
    }

    func saveRemote(baseURL: String, model: String, credentialIntent: RemoteCredentialIntent, enabled: Bool) async {
        do {
            if enabled { _ = try RemoteEndpoint(baseURL: baseURL, model: model) }
            let endpoint = RemoteCredentialIntent.normalizedEndpoint(baseURL)
            let hasExistingCredential = credentialIntent == .none ? try KeychainService.read(endpoint: endpoint) != nil : false
            if let value = try credentialIntent.valueToWrite(endpoint: endpoint, savedEndpoint: remoteBaseURL, hasExistingCredential: hasExistingCredential) {
                try KeychainService.save(value, endpoint: endpoint)
            }
            remoteBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            remoteModelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
            remoteEnabled = enabled
            defaults.set(remoteBaseURL, forKey: "remoteBaseURL")
            defaults.set(remoteModelName, forKey: "remoteModelName")
            defaults.set(enabled, forKey: "remoteEnabled")
            try await reloadProviders()
        } catch { report(error) }
    }

    func downloadModel(_ descriptor: LocalModelDescriptor) {
        guard downloadTask == nil, !isPreparingAutomaticModel else { return }
        let owner = UUID()
        manualDownloadOwner = owner
        downloadingModelID = descriptor.id
        downloadProgress = 0
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.modelStore.download(descriptor) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.manualDownloadOwner == owner else { return }
                        self.downloadProgress = progress
                    }
                }
                try await self.reloadProviders()
                // Installation may already be committed when Cancel arrives during
                // refresh. Keep those bytes/catalog, but skip the explicit selection.
                try Task.checkCancellation()
                self.selectedProviderID = descriptor.id
            } catch { if !Task.isCancelled { self.report(error) } }
            guard self.manualDownloadOwner == owner else { return }
            self.manualDownloadOwner = nil
            self.downloadingModelID = nil
            self.downloadProgress = nil
            self.downloadTask = nil
        }
    }

    func cancelDownload() {
        if automaticDownloadOwner != nil { cancelAutomaticPreparation() }
        else { downloadTask?.cancel() }
    }

#if DEBUG
    /// Controlled UI state only. Never starts a network request or installs weights.
    func beginControlledModelDownloadFixture() {
        guard downloadTask == nil else { return }
        downloadingModelID = LocalModelCatalog.defaultModel.id
        downloadProgress = 0.25
        downloadTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3_600)) } catch { }
            self?.downloadingModelID = nil
            self?.downloadProgress = nil
            self?.downloadTask = nil
        }
    }
#endif

    func importModel(from url: URL) async {
        cancelAutomaticPreparation()
        do {
            let descriptor = try await modelStore.importModel(from: url)
            try await reloadProviders()
            selectedProviderID = descriptor.id
        } catch { report(error) }
    }

    func removeModel(_ descriptor: LocalModelDescriptor) async {
        guard !isGenerating, !isPreparingAutomaticModel else { errorMessage = "Stop the response or automatic preparation before removing a model."; return }
        do {
            if let provider = localProviders[descriptor.id] { await provider.unload() }
            try await modelStore.remove(descriptor)
            localProviders[descriptor.id] = nil
            try await reloadProviders()
        } catch { report(error) }
    }

    func checkpoint() async {
        if let id = generatingConversationID { try? await persist(id) }
    }

    func report(_ error: Error) { errorMessage = error.localizedDescription }

    private func beginHistoryChange() -> Bool {
        guard !isLocalResourceAdmissionBlocked else { errorMessage = LocalHeavyWorkError.busy.localizedDescription; return false }
        guard !isChangingHistory else { errorMessage = "Wait for the current history operation to finish."; return false }
        guard !isSavingGeneratedImageRecord else { errorMessage = "Wait for the accepted image to finish saving before changing history."; return false }
        generatedImageOperation = nil; generatedImageTask?.cancel()
        cancelAutomaticPreparation()
        isChangingHistory = true
        return true
    }

    private func finishHistoryChange() {
        isChangingHistory = false
        performAttachmentCleanupIfReady()
    }

    private func requestAttachmentCleanup() {
        attachmentCleanupNeeded = true
        performAttachmentCleanupIfReady()
    }

    private func performAttachmentCleanupIfReady() {
        guard attachmentCleanupNeeded, attachmentImportJobs.isEmpty, generatedImageTask == nil, !isChangingHistory else { return }
        let attachments = conversations.flatMap(\.messages).flatMap(\.attachments) + pendingAttachments
        let retained = attachments.reduce(into: Set<String>()) { $0.formUnion($1.localRelativePaths) }
        do {
            try attachmentService.removeUnreferenced(keeping: retained)
            attachmentCleanupNeeded = false
        } catch { report(error) }
    }

    private func upsert(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) { conversations[index] = conversation }
        else { conversations.insert(conversation, at: 0) }
    }

    private func updateMessage(conversationID: UUID, messageID: UUID, update: (inout ChatMessage) -> Void) {
        guard let c = conversations.firstIndex(where: { $0.id == conversationID }),
              let m = conversations[c].messages.firstIndex(where: { $0.id == messageID }) else { return }
        update(&conversations[c].messages[m])
        conversations[c].updatedAt = Date()
    }

    private func persist(_ id: UUID) async throws {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        try await store.save(conversation)
    }
}

private struct AttachmentImportOutcome: Sendable {
    let attachments: [ChatAttachment]
    let errorMessage: String?
    let wasCancelled: Bool
}

private struct AttachmentImportJob {
    let reservedSlots: Int
    let task: Task<AttachmentImportOutcome, Never>
}

private enum AppError: LocalizedError {
    case importTooLarge
    var errorDescription: String? { "Choose an Orivyn JSON backup up to 50 MB." }
}

/// Single-use per-turn ownership, not a global permission to cancel by session.
/// Immutable public context lets UI recognize the first voice-created chat.
@MainActor
final class VoiceTurnTicket {
    let id = UUID()
    let ownerID: UUID
    let conversationID: UUID
    let originatingConversationID: UUID?
    let providerID: String
    fileprivate let modelID: UUID
    fileprivate let conversationRevision: UUID
    fileprivate let providerRevision: UUID
    fileprivate let composerContext: UUID
    fileprivate let composerRevision: UUID
    fileprivate let draft: String
    fileprivate var acceptedConversationRevision: UUID?
    fileprivate var acceptedComposerContext: UUID?
    fileprivate var isCancelled = false
    fileprivate var wasSubmitted = false

    fileprivate init(ownerID: UUID, modelID: UUID, conversationID: UUID, originatingConversationID: UUID?,
                     providerID: String, conversationRevision: UUID, providerRevision: UUID,
                     composerContext: UUID, composerRevision: UUID, draft: String) {
        self.ownerID = ownerID
        self.modelID = modelID
        self.conversationID = conversationID
        self.originatingConversationID = originatingConversationID
        self.providerID = providerID
        self.conversationRevision = conversationRevision
        self.providerRevision = providerRevision
        self.composerContext = composerContext
        self.composerRevision = composerRevision
        self.draft = draft
    }
}

enum VoiceTurnError: LocalizedError {
    case busy, attachmentsPending, contextChanged, invalidTicket, offlineRemote
    var errorDescription: String? {
        switch self {
        case .busy: return "Wait for the current response or history operation before starting voice conversation."
        case .attachmentsPending: return "Send or remove attached files and finish any imports before starting voice conversation. Your files have been kept."
        case .contextChanged: return "The conversation, model, or draft changed. Start a new voice turn in the current conversation."
        case .invalidTicket: return "This voice turn is no longer valid. Start a new voice turn."
        case .offlineRemote: return "You’re offline. Choose an available on-device model before starting voice conversation."
        }
    }
}

private struct AutomaticPreparationTicket {
    let id = UUID()
    let conversationID: UUID?
    let conversationRevision: UUID
    let providerRevision: UUID
    let composerRevision: UUID
    let draft: String
    let attachments: [UUID]
}

