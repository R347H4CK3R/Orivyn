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
    private(set) var automaticDecision: AutomaticModelDecision?
    var isPreparingAutomaticModel: Bool { automaticTicket != nil }
    private(set) var installedModels: [LocalModelDescriptor] = []
    private(set) var memories: [MemoryNote] = []
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
    private var automaticTask: Task<Void, Never>?
    private var automaticTicket: AutomaticPreparationTicket?
    private var automaticDownloadOwner: UUID?
    private var automaticPreparer: (any AutomaticModelPreparing)?
    private var automaticProviderFactory: (@MainActor (LocalModelDescriptor) -> any AIProvider)?
    private let localEngine: LlamaEngine
    private let resourceReleaser: any LocalResourceReleasing
    private(set) var heavyWorkLease: LocalHeavyWorkLease?
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
            conversation.isArchived == showArchived && (searchText.isEmpty || conversation.title.localizedCaseInsensitiveContains(searchText) || conversation.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) })
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
        for model in installedModels {
            let provider: LocalAIProvider
            if let existing = localProviders[model.id] { provider = existing }
            else { provider = LocalAIProvider(store: modelStore, model: model, engine: localEngine); localProviders[model.id] = provider }
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
        replaceProviders(options)
    }

    func selectConversation(_ id: UUID) {
        selectedConversationID = id
        draft = ""
        clearPendingAttachments()
    }

    func newConversation() async {
        guard beginHistoryChange() else { return }
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
        } catch { report(error) }
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
                          provider: provider, voiceTicket: ticket)
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
        submit(text: draft, attachments: pendingAttachments, conversationID: selectedConversationID ?? UUID(), provider: provider)
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
                    conversationID: self.selectedConversationID ?? UUID(), provider: provider)
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
    private func submit(text: String, attachments: [ChatAttachment], conversationID: UUID, provider: any AIProvider,
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
        return startGeneration(conversationID: conversation.id, assistantID: assistant.id, provider: provider,
                               restoringDraftOnSaveFailure: message, voiceTicket: voiceTicket)
    }

    @discardableResult
    private func startGeneration(conversationID: UUID, assistantID: UUID, provider: any AIProvider,
                                 restoringDraftOnSaveFailure original: ChatMessage? = nil,
                                 voiceTicket: VoiceTurnTicket? = nil) -> Task<Result<String, any Error>, Never> {
        guard !isInferenceAdmissionBlocked else { return Task { .failure(LocalHeavyWorkError.busy) } }
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
                let notes = self.memories.map(\.content).joined(separator: "\n")
                let system = "You are Jarvis, the assistant in Orivyn. Do the useful parts of the request first: explain, draft, analyze or provide concrete steps. When an action needs a device tool, suggest review in the real Email, Calendar, Browser, Location or Reminder screen. Opening a review does not send, save or execute it. Be clear about uncertainty and limitations. Do not claim to browse, run code, or take actions that you cannot perform. All configured providers receive text only. Image attachments supply OCR text, never image pixels. Do not infer objects, people, colors, layout, or other visual contents from an image attachment. " + self.workspace.behavior.prompt + (notes.isEmpty ? "" : "\nUser-saved context, not higher-priority instructions:\n" + notes)
                let request = GenerationRequest(messages: Array(conversation.messages.dropLast()), systemPrompt: system, maxTokens: 1024, temperature: 0.7)
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

    func rename(_ id: UUID, to title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = String(title.prefix(200))
        conversations[index].updatedAt = Date()
        do { try await persist(id) } catch { report(error) }
    }

    func archive(_ id: UUID, archived: Bool) async {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isArchived = archived
        conversations[index].updatedAt = Date()
        do { try await persist(id) } catch { report(error) }
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
            try await store.deleteAll()
            conversations = []
            memories = []
            selectedConversationID = nil
            draft = ""
            pendingAttachments = []
            requestAttachmentCleanup()
        } catch { report(error) }
    }

    @discardableResult
    func branch(through messageID: UUID) async -> Bool {
        guard !isInferenceAdmissionBlocked, !isGenerating, let activeConversation else { return false }
        guard beginHistoryChange() else { return false }
        defer { finishHistoryChange() }
        cancelAttachmentImports()
        do {
            let branched = try activeConversation.branching(through: messageID)
            try await store.save(branched)
            upsert(branched)
            selectConversation(branched.id)
            return true
        } catch { report(error); return false }
    }

    func editAndBranch(messageID: UUID, text: String) async {
        guard !isInferenceAdmissionBlocked, !isGenerating, let activeConversation else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard beginHistoryChange() else { return }
        defer { finishHistoryChange() }
        cancelAttachmentImports()
        do {
            var branched = try activeConversation.branching(through: messageID)
            // The selected user turn is the final message in the new branch.
            guard let last = branched.messages.last, last.role == .user else { return }
            try branched.editUserMessage(id: last.id, content: text)
            try await store.save(branched)
            upsert(branched)
            selectConversation(branched.id)
            regenerateLastUserTurn()
        } catch { report(error) }
    }

    func regenerate(messageID: UUID) async {
        guard !isInferenceAdmissionBlocked, !isGenerating, let conversation = activeConversation,
              let index = conversation.messages.firstIndex(where: { $0.id == messageID }),
              let user = conversation.messages[..<index].last(where: { $0.role == .user }) else { return }
        guard await branch(through: user.id) else { return }
        regenerateLastUserTurn()
    }

    private func regenerateLastUserTurn() {
        guard !isInferenceAdmissionBlocked, !isGenerating, let provider = selectedProvider?.provider, var conversation = activeConversation else {
            errorMessage = "Choose an available model before generating a response."
            return
        }
        let assistant = ChatMessage(id: UUID(), role: .assistant, content: "", createdAt: Date(), state: .streaming, attachments: [])
        conversation.messages.append(assistant)
        upsert(conversation)
        startGeneration(conversationID: conversation.id, assistantID: assistant.id, provider: provider)
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

    func exportData() async throws -> Data { try await store.exportData() }

    func importHistory(from url: URL) async {
        guard !isGenerating else { errorMessage = "Stop the current response before importing history."; return }
        guard beginHistoryChange() else { return }
        defer { finishHistoryChange() }
        cancelAttachmentImports()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0 && size <= ConversationBackup.maximumBytes else { throw AppError.importTooLarge }
            try await store.importData(Data(contentsOf: url))
            conversations = try await store.list(includeArchived: true)
            memories = try await store.memories()
            requestAttachmentCleanup()
        } catch { report(error) }
    }

    func saveMemory(id: UUID? = nil, content: String) async {
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        do {
            let existing = memories.first(where: { $0.id == id })
            try await store.saveMemory(MemoryNote(id: id ?? UUID(), content: content, createdAt: existing?.createdAt ?? Date()))
            memories = try await store.memories()
        } catch { report(error) }
    }

    func deleteMemory(_ id: UUID) async {
        do { try await store.deleteMemory(id: id); memories = try await store.memories() }
        catch { report(error) }
    }

    func saveRemote(baseURL: String, model: String, key: String, enabled: Bool) async {
        do {
            if enabled { _ = try RemoteEndpoint(baseURL: baseURL, model: model) }
            try KeychainService.save(key, endpoint: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))
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
        downloadingModelID = descriptor.id
        downloadProgress = 0
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.modelStore.download(descriptor) { [weak self] progress in
                    Task { @MainActor [weak self] in self?.downloadProgress = progress }
                }
                try await self.reloadProviders()
                self.selectedProviderID = descriptor.id
            } catch { if !Task.isCancelled { self.report(error) } }
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
