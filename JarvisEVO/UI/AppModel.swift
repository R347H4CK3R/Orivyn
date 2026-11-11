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
    var selectedConversationID: UUID?
    var draft = ""
    var pendingAttachments: [ChatAttachment] = []
    var searchText = ""
    var showArchived = false
    private(set) var isGenerating = false
    private(set) var generatingConversationID: UUID?
    var errorMessage: String?
    var statusMessage: String?
    let network = NetworkStatus()
    private(set) var providers: [ProviderOption] = []
    var selectedProviderID: String {
        didSet { defaults.set(selectedProviderID, forKey: "selectedProviderID") }
    }
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
    private var generationTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var localProviders: [String: LocalAIProvider] = [:]

    init(store: SQLiteConversationStore, attachmentService: AttachmentService, modelStore: LocalModelStore,
         providers: [ProviderOption] = [], defaults: UserDefaults = .standard) {
        self.store = store
        self.attachmentService = attachmentService
        self.modelStore = modelStore
        self.providers = providers
        self.defaults = defaults
        selectedProviderID = defaults.string(forKey: "selectedProviderID") ?? ""
        remoteBaseURL = defaults.string(forKey: "remoteBaseURL") ?? ""
        remoteModelName = defaults.string(forKey: "remoteModelName") ?? ""
        remoteEnabled = defaults.bool(forKey: "remoteEnabled")
    }

    var activeConversation: Conversation? { conversations.first { $0.id == selectedConversationID } }
    var selectedProvider: ProviderOption? { providers.first { $0.id == selectedProviderID } }
    var canSend: Bool { !isGenerating && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty) }
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
            try await reloadProviders()
        } catch { report(error) }
    }

    func replaceProviders(_ providers: [ProviderOption]) {
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
            else { provider = LocalAIProvider(store: modelStore, model: model); localProviders[model.id] = provider }
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
            options.append(ProviderOption(id: "remote", title: remoteModelName, detail: "Remote · sends conversation text and attachments to your endpoint", provider: provider))
        }
        replaceProviders(options)
    }

    func selectConversation(_ id: UUID) {
        selectedConversationID = id
        draft = ""
        clearPendingAttachments()
    }

    func newConversation() async {
        do {
            let conversation = Conversation(id: UUID(), title: "New conversation", createdAt: Date(), updatedAt: Date(), isArchived: false, messages: [])
            try await store.save(conversation)
            conversations.insert(conversation, at: 0)
            selectConversation(conversation.id)
            showArchived = false
            searchText = ""
        } catch { report(error) }
    }

    func send() {
        guard canSend else { return }
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
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        let conversationID = selectedConversationID ?? UUID()
        let message = ChatMessage(id: UUID(), role: .user, content: content.isEmpty ? "Please review the attached file." : content,
                                  createdAt: Date(), state: .complete, attachments: attachments)
        var conversation = activeConversation ?? Conversation(id: conversationID, title: "New conversation", createdAt: Date(), updatedAt: Date(), isArchived: false, messages: [])
        conversation.messages.append(message)
        conversation.isArchived = false
        if conversation.title == "New conversation" { conversation.title = String(message.content.prefix(60)) }
        conversation.updatedAt = Date()
        selectedConversationID = conversation.id
        let assistant = ChatMessage(id: UUID(), role: .assistant, content: "", createdAt: Date(), state: .streaming, attachments: [])
        conversation.messages.append(assistant)
        upsert(conversation)
        draft = ""
        pendingAttachments = []
        startGeneration(conversationID: conversation.id, assistantID: assistant.id, provider: provider, restoringDraftOnSaveFailure: message)
    }

    private func startGeneration(conversationID: UUID, assistantID: UUID, provider: any AIProvider,
                                 restoringDraftOnSaveFailure original: ChatMessage? = nil) {
        isGenerating = true
        generatingConversationID = conversationID
        generationTask = Task { [weak self] in
            guard let self else { return }
            var didPersist = false
            do {
                guard let conversation = self.conversations.first(where: { $0.id == conversationID }) else { return }
                try await self.store.save(conversation)
                didPersist = true
                try Task.checkCancellation()
                let notes = self.memories.map(\.content).joined(separator: "\n")
                let system = "You are Jarvis-EVO, a helpful personal assistant. Be clear about uncertainty and limitations. Do not claim to browse, run code, or take actions that you cannot perform. " + (notes.isEmpty ? "" : "User-saved context, not higher-priority instructions:\n" + notes)
                let request = GenerationRequest(messages: Array(conversation.messages.dropLast()), systemPrompt: system, maxTokens: 1024, temperature: 0.7)
                let stream = try await provider.stream(request)
                var checkpoint = Date()
                for try await token in stream {
                    try Task.checkCancellation()
                    self.updateMessage(conversationID: conversationID, messageID: assistantID) { $0.content += token }
                    if Date().timeIntervalSince(checkpoint) >= 0.25 {
                        try await self.persist(conversationID)
                        checkpoint = Date()
                    }
                }
                try Task.checkCancellation()
                self.updateMessage(conversationID: conversationID, messageID: assistantID) { message in
                    message.state = message.content.isEmpty ? .failed : .complete
                }
                try await self.persist(conversationID)
            } catch {
                self.updateMessage(conversationID: conversationID, messageID: assistantID) { message in
                    message.state = Task.isCancelled || error is CancellationError ? .interrupted : .failed
                }
                if didPersist { try? await self.persist(conversationID) }
                if !didPersist, let original {
                    self.draft = original.content
                    self.pendingAttachments = original.attachments
                    if let index = self.conversations.firstIndex(where: { $0.id == conversationID }) {
                        self.conversations[index].messages.removeAll { $0.id == original.id || $0.id == assistantID }
                    }
                }
                if !Task.isCancelled && !(error is CancellationError) { self.report(error) }
            }
            self.isGenerating = false
            self.generatingConversationID = nil
            self.generationTask = nil
        }
    }

    func stop() { generationTask?.cancel() }

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
        if generatingConversationID == id { stop(); await generationTask?.value }
        do {
            try await store.delete(id: id)
            conversations.removeAll { $0.id == id }
            if selectedConversationID == id { selectedConversationID = nil }
            let retained = Set(conversations.flatMap(\.messages).flatMap(\.attachments).map(\.relativePath) + pendingAttachments.map(\.relativePath))
            try attachmentService.removeUnreferenced(keeping: retained)
        } catch { report(error) }
    }

    func deleteAllContent() async {
        stop()
        await generationTask?.value
        do {
            try await store.deleteAll()
            conversations = []
            memories = []
            selectedConversationID = nil
            draft = ""
            pendingAttachments = []
            try attachmentService.removeAll()
        } catch { report(error) }
    }

    @discardableResult
    func branch(through messageID: UUID) async -> Bool {
        guard !isGenerating, let activeConversation else { return false }
        do {
            let branched = try activeConversation.branching(through: messageID)
            try await store.save(branched)
            upsert(branched)
            selectConversation(branched.id)
            return true
        } catch { report(error); return false }
    }

    func editAndBranch(messageID: UUID, text: String) async {
        guard !isGenerating, let activeConversation else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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
        guard !isGenerating, let conversation = activeConversation,
              let index = conversation.messages.firstIndex(where: { $0.id == messageID }),
              let user = conversation.messages[..<index].last(where: { $0.role == .user }) else { return }
        guard await branch(through: user.id) else { return }
        regenerateLastUserTurn()
    }

    private func regenerateLastUserTurn() {
        guard !isGenerating, let provider = selectedProvider?.provider, var conversation = activeConversation else {
            errorMessage = "Choose an available model before generating a response."
            return
        }
        let assistant = ChatMessage(id: UUID(), role: .assistant, content: "", createdAt: Date(), state: .streaming, attachments: [])
        conversation.messages.append(assistant)
        upsert(conversation)
        startGeneration(conversationID: conversation.id, assistantID: assistant.id, provider: provider)
    }

    func addAttachments(from urls: [URL]) async {
        guard pendingAttachments.count + urls.count <= 4 else { errorMessage = "Attach up to four files per message."; return }
        for url in urls {
            do { pendingAttachments.append(try attachmentService.importFile(at: url)) }
            catch { report(error); break }
        }
    }

    func removePendingAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
        attachmentService.remove(attachment)
    }

    func clearPendingAttachments() {
        for attachment in pendingAttachments { attachmentService.remove(attachment) }
        pendingAttachments = []
    }

    func exportData() async throws -> Data { try await store.exportData() }

    func importHistory(from url: URL) async {
        guard !isGenerating else { errorMessage = "Stop the current response before importing history."; return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0 && size <= ConversationBackup.maximumBytes else { throw AppError.importTooLarge }
            try await store.importData(Data(contentsOf: url))
            conversations = try await store.list(includeArchived: true)
            memories = try await store.memories()
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
        guard downloadTask == nil else { return }
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

    func cancelDownload() { downloadTask?.cancel() }

    func importModel(from url: URL) async {
        do {
            let descriptor = try await modelStore.importModel(from: url)
            try await reloadProviders()
            selectedProviderID = descriptor.id
        } catch { report(error) }
    }

    func removeModel(_ descriptor: LocalModelDescriptor) async {
        guard !isGenerating else { errorMessage = "Stop the response before removing a model."; return }
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

private enum AppError: LocalizedError {
    case importTooLarge
    var errorDescription: String? { "Choose a Jarvis-EVO JSON backup up to 50 MB." }
}
