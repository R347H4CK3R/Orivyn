import Foundation
import Observation

enum PeerHistoryReceiveError: Error { case unsavedOrStaleHistory }

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
    /// Changes on conversation selection, including switching away and back.
    var pluginResultConversationContext: UUID { conversationRevision }
    var pluginProposalProviderContext: UUID { providerRevision }
    func addPluginResultToDraft(executionID: UUID) throws {
        guard !isGenerating, let plugins else { throw PluginResultDraftError.stale }
        draft = try plugins.consumeResultDraft(executionID: executionID,
            conversationContext: conversationRevision, currentDraft: draft)
        isExternalComposerDraft = true
        // Existing attachments and history are deliberately untouched. No Send here.
    }

    private var storedPluginProposal: PendingChatPluginProposal?
    private var pluginProposalGeneration: UUID?
    var pendingPluginProposal: PendingChatPluginProposal? {
        guard let value = storedPluginProposal, let broker = plugins, broker.canReviewTools,
              value.isCurrent(conversation: conversationRevision, provider: providerRevision,
                  connection: broker.activeConnection?.id, catalog: broker.proposalCatalogID,
                  generation: pluginProposalGeneration),
              let assistant = activeConversation?.messages.first(where: { $0.id == value.assistantID }),
              assistant.role == .assistant, assistant.state == .complete || assistant.state == .streaming
        else { return nil }
        return value
    }
    func dismissPluginProposal(id: UUID) {
        if storedPluginProposal?.id == id { storedPluginProposal = nil }
    }
    func pluginProposalReviewRoute(id: UUID) -> ChatPluginReviewRoute? {
        guard !isGenerating, !isPreparingAutomaticModel,
              let value = pendingPluginProposal, value.id == id, let broker = plugins,
              let tool = broker.tools.first(where: { $0.name.utf8.elementsEqual(value.proposal.name.utf8) }),
              (try? tool.inputSchema.validate(value.proposal.arguments)) != nil else { return nil }
        return .init(id: value.id, tool: tool, arguments: value.proposal.arguments, request: value.request)
    }

    private var isExternalComposerDraft = false
    var draft = "" {
        didSet {
            if draft.isEmpty { isExternalComposerDraft = false }
            if oldValue != draft { composerDidChange() }
        }
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
    private(set) var isRemovingModel = false
    private var isImportingModel = false
    var isLocalResourceAdmissionBlocked: Bool {
        isRemovingModel || heavyWorkLease != nil || pressureReleaseTask != nil || thermalBlocksHeavyWork
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
    // Only importer-returned fresh files are ours to roll back without a complete
    // history snapshot. Existing/saved files still require the reference-aware sweep.
    private var ownedAttachmentImports: [UUID: ChatAttachment] = [:]
    private var isChangingHistory = false
    private var peerHistoryNeedsReload = false
    private var peerHistoryRecoveryInProgress = false
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

    private(set) var archiveJobsDirectory: URL?
    private(set) var verifiedReadDirectory: URL?
    func configureLocalWork(directory: URL) {
        archiveJobsDirectory = directory.appendingPathComponent("ArchiveRestoreJobs", isDirectory: true)
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

    func configurePlugins(directory: URL,
                          clientFactory: (@MainActor (MCPEndpoint, String?) throws -> any PluginMCPClient)? = nil) {
        do {
            if let clientFactory { plugins = try PluginBroker(directory: directory, clientFactory: clientFactory) }
            else { plugins = try PluginBroker(directory: directory) }
            pluginSetupError = nil
        }
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
                self.ownedAttachmentImports[image.id] = image
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
                try await self.saveConversation(conversation)
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
        isExternalComposerDraft = true
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
        // A suspended read must not race another load or a history transaction.
        guard !isLoading, !isChangingHistory else { return }
        attachmentHistoryIsLoaded = false
        ownedAttachmentImports.removeAll()
        isLoading = true
        defer { isLoading = false }
        do {
            conversations = try await store.list(includeArchived: true)
            attachmentHistoryIsLoaded = true
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
            try await saveConversation(conversation)
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

    var currentDirectLocalReadContract: LocalCompletionContract? {
        guard !isExternalComposerDraft else { return nil }
        return ChatLocalTaskRequest(draft: draft, hasAttachments: !pendingAttachments.isEmpty)?.proposedChecklist
            ?? NaturalLocalReadIntent(currentText: draft, hasAttachments: !pendingAttachments.isEmpty)?.contract
    }
    private var normalChatTurnForDraft: NormalChatLocalTurn? {
        guard currentDirectLocalReadContract == nil else { return nil }
        return NormalChatLocalTurn(goal: draft, hasAttachments: !pendingAttachments.isEmpty,
                                   isExternalDraft: isExternalComposerDraft)
    }
    var automaticLocalChatReadsAvailable: Bool {
        guard normalChatTurnForDraft != nil else { return false }
        if automaticModelsEnabled { return automaticProviderFactory == nil }
        return selectedProvider?.provider is LocalAIProvider
    }

    func validateNormalChatOrigin(_ binding: NormalChatReceiptBinding) throws {
        try Task.checkCancellation()
        guard !isInferenceAdmissionBlocked,
              binding.context.matches(conversationID: selectedConversationID,
                  conversationRevision: conversationRevision, providerRevision: providerRevision),
              generatingConversationID == binding.context.conversationID,
              let assistantID = binding.assistantID,
              let message = conversations.first(where: { $0.id == binding.context.conversationID })?.messages.last,
              message.id == assistantID, message.role == .assistant, message.state == .streaming else { throw CancellationError() }
    }

    func recordNormalChatReceipt(_ event: NormalChatReadEvent, binding: NormalChatReceiptBinding) async throws {
        try validateNormalChatOrigin(binding)
        guard let assistantID = binding.assistantID else { throw CancellationError() }
        let rendered = try event.rendered()
        updateMessage(conversationID: binding.context.conversationID, messageID: assistantID) { $0.content += rendered }
        // Required acknowledgement barrier: no next model/tool step on save error.
        try await persist(binding.context.conversationID)
        try validateNormalChatOrigin(binding)
        statusMessage = (event.action.name == "calculate" ? "Local calculation " : "Local read ") + event.phase.rawValue + ": " + event.action.name
    }

    func send() {
        guard canSend else { return }
        // Only the current typed request grants this narrow, read-only scope.
        // History, imported memory, model output and plugin metadata never enter it.
        let directContract = currentDirectLocalReadContract
        if let contract = directContract {
            let conversationID = selectedConversationID ?? UUID()
            selectedConversationID = conversationID
            let ownedConversationRevision = conversationRevision
            let ownedProviderRevision = providerRevision
            let read: @MainActor @Sendable (LocalCompletionContract.Action) async throws -> String = { [weak self] action in
                guard let self else { throw CancellationError() }
                try Task.checkCancellation()
                guard self.selectedConversationID == conversationID,
                      self.conversationRevision == ownedConversationRevision,
                      self.providerRevision == ownedProviderRevision else { throw CancellationError() }
                let result = try await LocalReadTools.executeAsync(name: action.name, arguments: action.arguments,
                    model: self, resultByteLimit: 4096)
                try Task.checkCancellation()
                guard self.selectedConversationID == conversationID,
                      self.conversationRevision == ownedConversationRevision,
                      self.providerRevision == ownedProviderRevision else { throw CancellationError() }
                return result
            }
            let provider: any AIProvider
            if contract.steps.count == 1, let action = contract.steps.first {
                statusMessage = "Reading locally: " + action.name
                provider = AutomaticLocalReadProvider(toolName: action.name) { try await read(action) }
            } else {
                statusMessage = "Reading locally: " + contract.steps.map(\.name).joined(separator: ", ")
                provider = AutomaticLocalReadPlanProvider(contract: contract, read: read)
            }
            submit(text: draft, attachments: [], conversationID: conversationID,
                provider: provider, providerID: provider.id)
            return
        }
        if !automaticModelsEnabled, let local = selectedProvider?.provider as? LocalAIProvider,
           let turn = normalChatTurnForDraft {
            submitNormalLocalChat(turn: turn, local: local)
            return
        }
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

    private func submitNormalLocalChat(turn: NormalChatLocalTurn, local: LocalAIProvider) {
        let conversationID = selectedConversationID ?? UUID()
        selectedConversationID = conversationID
        let binding = NormalChatReceiptBinding(context: .init(conversationID: conversationID,
            conversationRevision: conversationRevision, providerRevision: providerRevision))
        let provider = NormalChatLocalAgentProvider(turn: turn, model: local,
            validateContext: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.validateNormalChatOrigin(binding)
            },
            read: { [weak self] action in
                guard let self else { throw CancellationError() }
                try await self.validateNormalChatOrigin(binding)
                let result = try await LocalReadTools.executeAsync(name: action.name,
                    arguments: action.arguments, model: self, resultByteLimit: 4096, trustedGoal: turn.goal)
                try await self.validateNormalChatOrigin(binding)
                return result
            },
            record: { [weak self] event in
                guard let self else { throw CancellationError() }
                try await self.recordNormalChatReceipt(event, binding: binding)
            })
        var selected: any AIProvider = provider
        var proposalGeneration: UUID?
        if let broker = plugins, broker.canReviewTools, let connection = broker.activeConnection,
           (try? ChatPluginCatalog.validate(broker.tools, goal: turn.goal)) != nil,
           let request = PluginChatRequest(goal: turn.goal, conversation: conversationRevision,
               provider: providerRevision, connection: connection.id, catalog: broker.proposalCatalogID) {
            let generation = UUID()
            proposalGeneration = generation
            selected = ChatPluginProposalProvider(goal: turn.goal, tools: broker.tools, model: local, makeFallback: {
                    var fresh = provider
                    fresh.deadline = .now.advanced(by: .seconds(120))
                    return fresh
                },
                validateContext: { [weak self] in
                    guard let self else { throw CancellationError() }
                    try await self.validateChatPluginProposal(request: request, generation: generation, binding: binding)
                }, publish: { [weak self] proposal in
                    guard let self else { throw CancellationError() }
                    try await self.publishChatPluginProposal(proposal, request: request, generation: generation, binding: binding)
                })
        }
        statusMessage = proposalGeneration == nil
            ? "Thinking on device; local tool receipts will appear in chat."
            : "Checking connected tools on device; any suggested call requires your review."
        submit(text: draft, attachments: [], conversationID: conversationID, provider: selected, providerID: selected.id,
            preparedAssistant: { binding.assistantID = $0; self.pluginProposalGeneration = proposalGeneration })
    }

    private func validateChatPluginProposal(request: PluginChatRequest, generation: UUID,
                                           binding: NormalChatReceiptBinding) throws {
        try validateNormalChatOrigin(binding)
        guard pluginProposalGeneration == generation, let broker = plugins, broker.canReviewTools,
              request.matches(conversation: conversationRevision, provider: providerRevision,
                  connection: broker.activeConnection?.id, catalog: broker.proposalCatalogID)
        else { throw CancellationError() }
    }
    private func publishChatPluginProposal(_ proposal: PluginToolProposal, request: PluginChatRequest,
                                          generation: UUID, binding: NormalChatReceiptBinding) throws {
        try validateChatPluginProposal(request: request, generation: generation, binding: binding)
        guard let assistantID = binding.assistantID, let broker = plugins,
              let tool = broker.tools.first(where: { $0.name.utf8.elementsEqual(proposal.name.utf8) })
        else { throw CancellationError() }
        try tool.inputSchema.validate(proposal.arguments)
        storedPluginProposal = .init(id: UUID(), proposal: proposal, request: request,
            assistantID: assistantID, generationID: generation, createdAt: Date())
        statusMessage = "Connected-tool proposal prepared, not executed."
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
                if let local = provider as? LocalAIProvider, let turn = self.normalChatTurnForDraft {
                    self.submitNormalLocalChat(turn: turn, local: local)
                } else {
                    self.submit(text: self.draft, attachments: self.pendingAttachments,
                        conversationID: self.selectedConversationID ?? UUID(), provider: provider, providerID: decision.model.id)
                }
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
                        voiceTicket: VoiceTurnTicket? = nil,
                        preparedAssistant: ((UUID) -> Void)? = nil) -> Task<Result<String, any Error>, Never> {
        guard !isInferenceAdmissionBlocked else { return Task { .failure(LocalHeavyWorkError.busy) } }
        storedPluginProposal = nil
        pluginProposalGeneration = nil
        let submittedExternalOrigin = isExternalComposerDraft
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
        preparedAssistant?(assistant.id)
        applyingOwnedComposerUpdate {
            draft = ""
            pendingAttachments = []
            // A Photos transfer started for this draft must not attach itself to the next draft after Send.
            cancelAttachmentImports()
        }
        voiceTicket?.acceptedComposerContext = attachmentImportEpoch
        return startGeneration(conversationID: conversation.id, assistantID: assistant.id, provider: provider, providerID: providerID,
                               restoringDraftOnSaveFailure: message, restoringDraftExternalOrigin: submittedExternalOrigin, voiceTicket: voiceTicket)
    }

    @discardableResult
    private func startGeneration(conversationID: UUID, assistantID: UUID, provider: any AIProvider, providerID: String,
                                 restoringDraftOnSaveFailure original: ChatMessage? = nil,
                                 restoringDraftExternalOrigin: Bool = false,
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
                try await self.saveConversation(conversation)
                didPersist = true
                self.isSavingSubmittedTurn = false
                try self.validateGeneration(voiceTicket)
                let currentGoal = conversation.messages.last(where: { $0.role == .user })?.content ?? ""
                let toolOwnsMemoryReads = ["chat-plugin-proposal", "normal-chat-local-agent", "automatic-local-read", "automatic-local-read-plan"].contains(providerID)
                let memoryContext = try await MemoryContextBuilder.buildAsync(
                    notes: toolOwnsMemoryReads || NormalChatLocalTurn.disallowsReads(currentGoal) ? [] : self.memories,
                    query: currentGoal,
                    maximumBytes: providerID == "remote" ? 1024 : 512)
                try self.validateGeneration(voiceTicket)
                self.lastMemoryContextSummary = memoryContext.totalCount == 0 ? nil :
                    "Latest prepared context selected \(memoryContext.includedCount) of \(memoryContext.totalCount) saved notes; scanned \(memoryContext.scannedCount)."
                    + (memoryContext.truncated ? " Some context was omitted or shortened; all original notes remain saved." : "")

                let system = ChatResponsePolicy.instructions + "\n" + AppSelfKnowledge.prompt(providerID: providerID) + "\n" + self.workspace.behavior.prompt + (memoryContext.text.isEmpty ? "" : "\n" + memoryContext.text)
                let request = GenerationRequest(messages: Array(conversation.messages.dropLast()), systemPrompt: system, maxTokens: 1024, temperature: 0.7, conciseQwen3: self.conciseQwen3)
                let stream = try await provider.stream(request)
                var checkpoint = Date()
                var answerStream = ChatAnswerStream()
                for try await token in stream {
                    try self.validateGeneration(voiceTicket)
                    let visible = answerStream.append(token)
                    self.updateMessage(conversationID: conversationID, messageID: assistantID) { $0.content += visible }
                    if Date().timeIntervalSince(checkpoint) >= 0.25 {
                        try await self.persist(conversationID)
                        checkpoint = Date()
                    }
                }
                try self.validateGeneration(voiceTicket)
                let suffix = answerStream.finish()
                self.updateMessage(conversationID: conversationID, messageID: assistantID) { $0.content += suffix }
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
                            self.isExternalComposerDraft = restoringDraftExternalOrigin
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
            try await saveConversation(proposed)
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
            try await saveConversation(proposed)
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
            attachmentHistoryIsLoaded = true
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
            try await saveConversation(branched)
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
            try await saveConversation(branched)
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
            try await saveConversation(branched)
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
        for attachment in result.attachments { ownedAttachmentImports[attachment.id] = attachment }
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

    func prepareTextExport(ids: Set<UUID>) async throws -> ReviewedTextSnapshot {
        guard !isGenerating, !isChangingHistory, !isLoading, !isSavingSubmittedTurn else { throw TextSnapshotError.busy }
        let value = try await store.exportTextSnapshot(ids: ids)
        try Task.checkCancellation()
        return value
    }



    /// Internal receive boundary. The caller supplies an authenticated, approved
    /// transfer and owns cancellation; this method grants no network authority.
    func performPeerHistoryReceive(_ operation: @MainActor () async throws -> Void) async throws {
        try Task.checkCancellation()
        guard canBeginHeavyWork, !peerHistoryNeedsReload,
              beginHistoryChange() else { throw TextSnapshotError.busy }
        var releaseHistory = true
        defer { if releaseHistory { finishHistoryChange() } }
        // Invalidate cleanup authority before any read that can reveal stale or
        // unreadable history; failure must never sweep files from the old view.
        attachmentHistoryIsLoaded = false
        let persisted = try await store.list(includeArchived: true)
        guard persisted.sorted(by: { $0.id.uuidString < $1.id.uuidString })
                == conversations.sorted(by: { $0.id.uuidString < $1.id.uuidString }) else {
            throw PeerHistoryReceiveError.unsavedOrStaleHistory
        }
        // Equality establishes fresh cleanup authority. A canceled preflight
        // can release ownership safely; rejected preflights remain retryable.
        attachmentHistoryIsLoaded = true
        try Task.checkCancellation()
        // A failed transfer can still have committed before losing its receipt.
        // No attachment sweep may use the old snapshot after this point.
        attachmentHistoryIsLoaded = false
        var transferError: (any Error)?
        do { try await operation() } catch { transferError = error }
        do {
            // Deliberately reconcile even when this task was canceled. list()
            // performs a read and does not consult the task cancellation flag.
            conversations = try await store.list(includeArchived: true)
            conversationRevision = UUID()
            attachmentHistoryIsLoaded = true
            requestAttachmentCleanup()
        } catch {
            peerHistoryNeedsReload = true
            releaseHistory = false
            report(error)
            throw error
        }
        if let transferError { throw transferError }
    }

    /// A failed post-receive read retains the existing mutation lock. Only a
    /// complete reload releases it; concurrent recoveries cannot unlock early.
    func recoverPeerHistoryReceive() async throws {
        guard peerHistoryNeedsReload, !peerHistoryRecoveryInProgress else { throw TextSnapshotError.busy }
        peerHistoryRecoveryInProgress = true
        defer { peerHistoryRecoveryInProgress = false }
        do {
            conversations = try await store.list(includeArchived: true)
            conversationRevision = UUID()
            attachmentHistoryIsLoaded = true
            peerHistoryNeedsReload = false
            requestAttachmentCleanup()
            finishHistoryChange()
        } catch {
            report(error)
            throw error
        }
    }

    #if ORIVYN_PEER_TLS_SPIKE && canImport(Network) && canImport(Security) && canImport(CryptoKit)
    /// Normal builds do not expose this transport. Pairing/scope consent remains
    /// the caller's responsibility; the exchange revalidates pins and epoch.
    func receivePeerTextRevisions(approvedSourceIDs: Set<UUID>, expectedEpoch: UUID,
                                  over channel: PeerTLSProbe.AuthenticatedChannel) async throws {
        defer { channel.cancel() }
        try await performPeerHistoryReceive {
            _ = try await PeerTextRevisionExchange.receive(approvedSourceIDs: approvedSourceIDs,
                expectedEpoch: expectedEpoch, store: self.store, over: channel)
        }
    }
    #endif

    func importHistory(from url: URL, policy: BackupImportPolicy = .preserveLocal) async {
        guard !isGenerating else { errorMessage = "Stop the current response before importing history."; return }
        guard beginHistoryChange() else { return }
        defer { finishHistoryChange() }
        cancelAttachmentImports()
        do {
            let data = try await BackupFileReader.read(url)
            try Task.checkCancellation()
            // A committed import can precede a failing reload. Keep its files until
            // a complete history snapshot has been read successfully.
            attachmentHistoryIsLoaded = false
            ownedAttachmentImports.removeAll()
            let summary = try await store.importData(data, policy: policy)
            conversations = try await store.list(includeArchived: true)
            attachmentHistoryIsLoaded = true
            memories = try await store.memories()
            statusMessage = summary.description
            requestAttachmentCleanup()
        } catch { report(error) }
    }

    private func archiveRoot() throws -> URL {
        guard let root = archiveJobsDirectory else { throw ArchiveRestoreService.Failure.invalidJob }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }
    private func runArchiveWork<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        let worker = Task.detached(priority: .utility, operation: body)
        return try await withTaskCancellationHandler {
            let value = try await worker.value
            try Task.checkCancellation(); return value
        } onCancel: { worker.cancel() }
    }
    private func archiveViewReview(_ value: ArchiveRestoreService.Review) -> ArchiveRestoreView.Review {
        .init(jobID: value.jobID, conversationCount: value.conversationCount, messageCount: value.messageCount,
              unresolvedCount: value.unresolvedCount, omittedCount: value.omittedCount,
              retainedFileCount: value.retainedFileCount, archiveSHA256: value.archiveSHA256)
    }
    private func archiveServiceReview(_ value: ArchiveRestoreView.Review) -> ArchiveRestoreService.Review {
        .init(jobID: value.jobID, conversationCount: value.conversationCount, messageCount: value.messageCount,
              unresolvedCount: value.unresolvedCount, omittedCount: value.omittedCount,
              retainedFileCount: value.retainedFileCount, archiveSHA256: value.archiveSHA256)
    }
    func retainedArchiveInventoryReviews() async throws -> [ArchiveRestoreView.Review] {
        let root = try archiveRoot()
        return try await runArchiveWork { try ArchiveRestoreService.listInventoryReviews(jobsRoot: root) }.map(archiveViewReview)
    }
    func retainedArchiveInventory(_ value: ArchiveRestoreView.Review, offset: Int) async throws -> ArchiveRestoreInventory.Page {
        guard !isGenerating, beginHistoryChange() else { throw TextSnapshotError.busy }
        defer { finishHistoryChange() }
        await resourceReleaser.unload()
        try Task.checkCancellation()
        let root = try archiveRoot(), review = archiveServiceReview(value)
        return try await runArchiveWork { try ArchiveRestoreService.retainedInventory(review: review, jobsRoot: root, offset: offset) }
    }
    func retainedArchiveAttachmentFiles(_ value: ArchiveRestoreView.Review, offset: Int) async throws -> ArchiveRestoreService.AttachmentFiles {
        guard !isGenerating, !isSavingSubmittedTurn, attachmentImportJobs.isEmpty, beginHistoryChange() else { throw TextSnapshotError.busy }
        defer { finishHistoryChange() }
        await resourceReleaser.unload()
        try Task.checkCancellation()
        let root = try archiveRoot(), review = archiveServiceReview(value)
        return try await runArchiveWork { try ArchiveRestoreService.attachmentFiles(review: review, jobsRoot: root, offset: offset) }
    }
    func retainedArchiveAttachmentMessages(_ value: ArchiveRestoreView.Review, offset: Int, query: String) async throws -> ArchiveRestoreService.AttachmentMessages {
        guard !isGenerating, !isSavingSubmittedTurn, attachmentImportJobs.isEmpty, beginHistoryChange() else { throw TextSnapshotError.busy }
        defer { finishHistoryChange() }
        await resourceReleaser.unload()
        try Task.checkCancellation()
        let root = try archiveRoot(), review = archiveServiceReview(value)
        return try await runArchiveWork { try ArchiveRestoreService.attachmentMessages(review: review, jobsRoot: root, offset: offset, query: query) }
    }
    func reviewArchiveAttachment(_ value: ArchiveRestoreView.Review, file: ArchiveRestoreService.AttachmentFile,
                                 message: ArchiveRestoreService.AttachmentMessage) async throws -> (candidate: ArchiveRestoreService.AttachmentCandidate, message: ChatMessage) {
        guard !isGenerating, !isSavingSubmittedTurn, attachmentImportJobs.isEmpty, beginHistoryChange() else { throw TextSnapshotError.busy }
        defer { finishHistoryChange() }
        await resourceReleaser.unload()
        try Task.checkCancellation()
        let root = try archiveRoot(), review = archiveServiceReview(value)
        let candidate = try await runArchiveWork { try ArchiveRestoreService.manualAttachmentCandidate(review: review, jobsRoot: root, file: file, message: message) }
        _ = try await store.archiveAttachmentSupplementReceipt(source: candidate.source, expectedEpoch: candidate.expectedEpoch)
        try Task.checkCancellation()
        return (candidate, try await currentArchiveAttachmentMessage(candidate))
    }

    private func currentArchiveAttachmentMessage(_ candidate: ArchiveRestoreService.AttachmentCandidate) async throws -> ChatMessage {
        guard try await store.textReceiveEpoch() == candidate.expectedEpoch,
              let conversation = try await store.load(id: candidate.source.conversationID) else {
            throw ArchiveAttachmentSupplement.Failure.changed
        }
        let matches = conversation.messages.filter { $0.id == candidate.source.messageID }
        guard matches.count == 1 else { throw ArchiveAttachmentSupplement.Failure.changed }
        var core = matches[0]; core.attachments = []
        guard core == candidate.originalMessage else { throw ArchiveAttachmentSupplement.Failure.changed }
        return matches[0]
    }

    func reviewArchiveAttachment(_ value: ArchiveRestoreView.Review, candidate: ArchiveRestoreService.AttachmentCandidate) async throws -> ChatMessage {
        guard !isGenerating, !isSavingSubmittedTurn, attachmentImportJobs.isEmpty, beginHistoryChange() else { throw TextSnapshotError.busy }
        defer { finishHistoryChange() }
        guard value.archiveSHA256 == candidate.source.archiveSHA256, candidate.source.origin == .userReviewed else { throw ArchiveAttachmentSupplement.Failure.invalid }
        // Lookup validates the immutable text receipt and epoch even when this
        // source has not been attached. It never copies or activates a file.
        _ = try await store.archiveAttachmentSupplementReceipt(source: candidate.source, expectedEpoch: candidate.expectedEpoch)
        try Task.checkCancellation()
        return try await currentArchiveAttachmentMessage(candidate)
    }

    func commitArchiveAttachment(_ value: ArchiveRestoreView.Review, candidate: ArchiveRestoreService.AttachmentCandidate,
                                 expectedMessage: ChatMessage, progress: @escaping ArchiveRestoreView.Progress) async throws -> ArchiveRestoreView.CommitOutcome {
        guard !isGenerating, !isSavingSubmittedTurn, attachmentImportJobs.isEmpty, beginHistoryChange() else { throw TextSnapshotError.busy }
        // Holds the existing app-private history/attachment maintenance lock across
        // verification, importer ownership, SQLite commit, and catalog refresh.
        var releaseHistory = true
        defer { if releaseHistory { finishHistoryChange() } }
        guard value.archiveSHA256 == candidate.source.archiveSHA256, candidate.source.origin == .userReviewed else { throw ArchiveAttachmentSupplement.Failure.invalid }
        if try await store.archiveAttachmentSupplementReceipt(source: candidate.source, expectedEpoch: candidate.expectedEpoch) != nil {
            return .committed("This source already has a saved attachment receipt. No file was copied or attached again, including if you removed it later.")
        }
        guard try await currentArchiveAttachmentMessage(candidate) == expectedMessage else { throw ArchiveAttachmentSupplement.Failure.changed }
        progress("Releasing local model memory before verifying the reviewed attachment")
        await resourceReleaser.unload()
        try Task.checkCancellation()
        let root = try archiveRoot(), review = archiveServiceReview(value)
        progress("Rechecking preserved archive and your exact file/message selection")
        let staged = try await ArchiveOwnedFileWork.run { try ArchiveRestoreService.stageAttachment(candidate: candidate, review: review, jobsRoot: root) }
        defer { try? FileManager.default.removeItem(at: staged) }
        try Task.checkCancellation()
        // Never remove a pre-existing/shared file, even if a faulty importer
        // returns a colliding identity. The production importer allocates UUIDs.
        let existingNames = Set(try FileManager.default.contentsOfDirectory(atPath: attachmentService.directory.path))
        var attachment = try await attachmentImporter.importAttachment(.file(staged))
        let ownsNewFiles = attachment.localRelativePaths.isDisjoint(with: existingNames)
        var committed = false
        defer { if !committed && ownsNewFiles { attachmentService.remove(attachment) } }
        guard ownsNewFiles else { throw ArchiveAttachmentSupplement.Failure.conflict }
        attachment.name = String(candidate.source.relativePath.split(separator: "/").last ?? "Attachment")
        attachment.name = String(attachment.name.prefix(200))
        try ArchiveAttachmentSupplement.validate(attachment, source: candidate.source)
        guard attachmentService.url(for: attachment) != nil else { throw ArchiveAttachmentSupplement.Failure.invalid }
        let directory = attachmentService.directory, importedPath = attachment.relativePath, source = candidate.source
        _ = try await runArchiveWork {
            try ArchiveAttachmentAssociation.verify(root: directory, relativePath: importedPath, bytes: source.bytes, sha256: source.sha256)
        }
        try Task.checkCancellation()
        progress("Saving only the reviewed attachment association atomically")
        _ = try await store.applyArchiveAttachmentSupplement(source: source, expectedEpoch: candidate.expectedEpoch,
            expectedMessage: expectedMessage, attachment: attachment)
        committed = true // A durable receipt, never a reason to delete its file.
        attachmentHistoryIsLoaded = false; peerHistoryNeedsReload = true
        let result = "Reviewed attachment saved. Original archive and unlinked reference records are unchanged; other media is not claimed as restored."
        do {
            conversations = try await store.list(includeArchived: true)
            conversationRevision = UUID()
            attachmentHistoryIsLoaded = true; peerHistoryNeedsReload = false
        } catch {
            releaseHistory = false
            return .committedReloadPending(result + " History editing is locked until reload succeeds. Refresh retained preparations or reopen the app.")
        }
        statusMessage = result
        return .committed(result)
    }

    func prepareArchiveRestore(_ url: URL, progress: @escaping ArchiveRestoreView.Progress) async throws -> ArchiveRestoreView.Review {
        guard !isGenerating, beginHistoryChange() else { throw TextSnapshotError.busy }
        defer { finishHistoryChange() }
        progress("Releasing local model memory before archive preparation")
        await resourceReleaser.unload()
        try Task.checkCancellation()
        let root = try archiveRoot(), epoch = try await store.textReceiveEpoch()
        let review = try await ArchiveRestoreFileReader.read(url) { selected in
            try ArchiveRestoreService.prepare(source: selected, jobsRoot: root, expectedEpoch: epoch, progress: progress)
        }
        return archiveViewReview(review)
    }
    func retainedArchiveReviews(progress: @escaping ArchiveRestoreView.Progress) async throws -> [ArchiveRestoreView.Review] {
        if peerHistoryNeedsReload {
            try await recoverPeerHistoryReceive()
            progress("Committed history reloaded; history editing is available again.")
        }
        let root = try archiveRoot()
        let retained = try await runArchiveWork { try ArchiveRestoreService.inspectRetainedJobs(jobsRoot: root) }
        if !retained.incompleteJobs.isEmpty {
            progress("\(retained.incompleteJobs.count) incomplete/damaged preparations retained. Import status could not be determined from preparation files; originals are retained.")
        }
        let recovered = try await ArchiveRestoreRecovery.reconcile(retained.reviews,
            isCommitted: { hash in try await self.store.archiveRestoreReceipt(archiveSHA256: hash) != nil },
            markCommitted: { review in
                try await self.runArchiveWork { try ArchiveRestoreService.markCommitted(review: review, jobsRoot: root) }
            })
        if !recovered.committedJobs.isEmpty { progress("Recovered \(recovered.committedJobs.count) committed preparations from database receipts; no duplicate import is needed.") }
        if !recovered.maintenancePending.isEmpty { progress("\(recovered.maintenancePending.count) committed preparation markers still need maintenance. History is already saved.") }
        return recovered.ready.map(archiveViewReview)
    }
    func commitArchiveRestore(_ value: ArchiveRestoreView.Review, progress: @escaping ArchiveRestoreView.Progress) async throws -> ArchiveRestoreView.CommitOutcome {
        guard !isGenerating, beginHistoryChange() else { throw TextSnapshotError.busy }
        var releaseHistory = true
        defer { if releaseHistory { finishHistoryChange() } }
        progress("Releasing local model memory before restore verification")
        await resourceReleaser.unload()
        try Task.checkCancellation()
        let root = try archiveRoot(), review = archiveServiceReview(value)
        let plan = try await runArchiveWork { try ArchiveRestoreService.verifyForCommit(review: review, jobsRoot: root, progress: progress) }
        try Task.checkCancellation()
        progress("Committing reviewed conversations atomically. Existing local records are preserved.")
        let receipt = try await store.applyArchiveRestore(jobID: review.jobID, archiveSHA256: review.archiveSHA256,
            expectedEpoch: plan.expectedEpoch, conversations: plan.conversations)
        // From this point the receipt is authoritative: failures cannot be reported as rollback.
        var pending: [String] = []
        var reloadFailed = false
        do { try await runArchiveWork { try ArchiveRestoreService.markCommitted(review: review, jobsRoot: root) } }
        catch { pending.append("Recovery status could not be refreshed; the database receipt is saved.") }
        attachmentHistoryIsLoaded = false; peerHistoryNeedsReload = true
        do {
            conversations = try await store.list(includeArchived: true)
            conversationRevision = UUID()
            attachmentHistoryIsLoaded = true; peerHistoryNeedsReload = false
        } catch {
            releaseHistory = false
            reloadFailed = true
            pending.append("History editing is locked until reload succeeds. Refresh retained preparations or reopen the app to retry.")
        }
        let result = "Restore receipt verified: \(receipt.writtenConversations) added, \(receipt.preservedConversations) existing conversations preserved. \(review.unresolvedCount) media references remain unlinked; original files are retained."
        statusMessage = result
        if reloadFailed { return .committedReloadPending(result + " " + pending.joined(separator: " ")) }
        if !pending.isEmpty { return .committedMaintenancePending(result + " " + pending.joined(separator: " ")) }
        return .committed(result)
    }

    /// Review is additive; reuse the SQLite transaction so a failed write adds nothing.
    @discardableResult
    func importFolderMemories(_ incoming: [MemoryNote]) async -> Bool {
        guard !isGenerating, beginHistoryChange() else { return false }
        defer { finishHistoryChange() }
        do {
            try Task.checkCancellation()
            let summary = try await store.importMemoryNotes(incoming)
            memories = try await store.memories()
            statusMessage = summary.description
            return true
        } catch { report(error); return false }
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
        guard !isRemovingModel, !isImportingModel, downloadTask == nil, !isPreparingAutomaticModel else { return }
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
        guard !isRemovingModel, !isImportingModel, downloadTask == nil else {
            errorMessage = "Wait for the current model operation to finish."; return
        }
        isImportingModel = true
        defer { isImportingModel = false }
        cancelAutomaticPreparation()
        do {
            let descriptor = try await modelStore.importModel(from: url)
            try await reloadProviders()
            selectedProviderID = descriptor.id
        } catch { report(error) }
    }

    func removeModel(_ descriptor: LocalModelDescriptor) async {
        guard !isLocalResourceAdmissionBlocked, !isGenerating, !isPreparingAutomaticModel,
              !isImportingModel, downloadTask == nil else {
            errorMessage = "Wait for the current response, model operation, or local workspace to finish before removing a model."; return
        }
        // Reserve before unload suspends: a newly submitted turn must not race
        // verification/loading against deletion of its selected model file.
        isRemovingModel = true
        defer { isRemovingModel = false }
        do {
            try Task.checkCancellation()
            await resourceReleaser.unload()
            try Task.checkCancellation()
            try await modelStore.remove(descriptor)
            localProviders[descriptor.id] = nil
            try await reloadProviders()
        } catch { if !(error is CancellationError) { report(error) } }
    }

    func checkpoint() async {
        if let id = generatingConversationID { try? await persist(id) }
    }

    func report(_ error: Error) { errorMessage = error.localizedDescription }

    private func beginHistoryChange() -> Bool {
        guard !isLoading else { errorMessage = "Wait for history to finish loading."; return false }
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

    // Cleanup must never infer orphaned files from an absent or stale history snapshot.
    private var attachmentHistoryIsLoaded = false

    private func performAttachmentCleanupIfReady() {
        guard attachmentCleanupNeeded, attachmentImportJobs.isEmpty, generatedImageTask == nil,
              !isChangingHistory else { return }
        let attachments = conversations.flatMap(\.messages).flatMap(\.attachments) + pendingAttachments
        let retained = attachments.reduce(into: Set<String>()) { $0.formUnion($1.localRelativePaths) }
        // Roll back only fresh imports whose ownership has not been transferred
        // to a successful save. Never enumerate/delete unknown persisted files here.
        let abandoned = ownedAttachmentImports.values.filter { $0.localRelativePaths.isDisjoint(with: retained) }
        for attachment in abandoned {
            attachmentService.remove(attachment)
            ownedAttachmentImports.removeValue(forKey: attachment.id)
        }
        guard attachmentHistoryIsLoaded else { return }
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

    private func saveConversation(_ conversation: Conversation) async throws {
        try await store.save(conversation)
        let savedNames = conversation.messages.flatMap(\.attachments)
            .reduce(into: Set<String>()) { $0.formUnion($1.localRelativePaths) }
        // A saved branch may refer to either name of an owned image. Once durable,
        // deletion belongs to a complete persisted-history snapshot, not rollback.
        ownedAttachmentImports = ownedAttachmentImports.filter {
            $0.value.localRelativePaths.isDisjoint(with: savedNames)
        }
    }

    private func persist(_ id: UUID) async throws {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        try await saveConversation(conversation)
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




/// Ephemeral origin binding; never decoded from chat text, imports or receipts.
@MainActor
final class NormalChatReceiptBinding {
    let context: ChatLocalTaskContext
    var assistantID: UUID?
    init(context: ChatLocalTaskContext, assistantID: UUID? = nil) {
        self.context = context; self.assistantID = assistantID
    }
}

#if DEBUG
extension AppModel {
    /// Presentation-only fixture. Does not assign pending state or weaken production guards.
    func beginPluginPresentationFixture() throws {
        guard RootViewRegressionFixtureHost.requestedMode == "plugin-suggestion",
              let turn = normalChatTurnForDraft,
              let conversationID = selectedConversationID, let broker = plugins,
              broker.canReviewTools, let connection = broker.activeConnection,
              let request = PluginChatRequest(goal: turn.goal, conversation: conversationRevision,
                  provider: providerRevision, connection: connection.id, catalog: broker.proposalCatalogID)
        else { throw CancellationError() }
        let binding = NormalChatReceiptBinding(context: .init(conversationID: conversationID,
            conversationRevision: conversationRevision, providerRevision: providerRevision))
        let generation = UUID()
        let provider = ChatPluginProposalProvider(goal: request.goal, tools: broker.tools,
            model: PluginPresentationFixtureModel(), makeFallback: { PluginPresentationFixtureModel() },
            validateContext: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.validateChatPluginProposal(request: request, generation: generation, binding: binding)
            }, publish: { [weak self] proposal in
                guard let self else { throw CancellationError() }
                try await self.publishChatPluginProposal(proposal, request: request, generation: generation, binding: binding)
            })
        submit(text: request.goal, attachments: [], conversationID: conversationID, provider: provider, providerID: provider.id,
               preparedAssistant: { binding.assistantID = $0; self.pluginProposalGeneration = generation })
    }
}
#endif
