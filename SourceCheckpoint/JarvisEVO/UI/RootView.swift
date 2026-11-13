import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import AVFoundation

struct RootView: View {
    @Bindable var model: AppModel
    @State private var voice = VoiceService()
    @State private var incoming = IncomingTextInbox.shared
    @State private var reviewingTool: NativeToolSuggestion?
    @State private var reviewingIncoming: IncomingTextRequest?
    @State private var showHistory = false
    @State private var workspaceSection: WorkspaceSection = .chat
    @State private var showModels = false
    @State private var showSettings = false
    private struct EditingMessage: Identifiable { let id = UUID(); let message: ChatMessage; let conversationID: UUID }
    @State private var editingMessage: EditingMessage?
    @State private var selectingText: ChatMessage?
    @State private var copied = false
    @State private var dictationPrefix = ""
    @State private var dictationTask: Task<Void, Never>?
    @State private var dictationID: UUID?
    @State private var voiceSession: VoiceConversationSession?
    @State private var offersPrivacySettings = false
    @State private var pickerRequest: AttachmentPickerRequest?
    @State private var pickerOwnership = AttachmentPickerOwnership()
    @State private var transferTask: Task<Void, Never>?
    @State private var transferID: UUID?
    @State private var previewAttachment: ChatAttachment?
    @State private var followsTranscript = true
    @State private var userIsScrolling = false
    @State private var transcriptNearBottom = true
    @FocusState private var composerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var inputLineHeight: CGFloat = 22

    init(model: AppModel) { self.model = model }

    #if DEBUG
    // Native touch/drag regression tests may supply controlled speech hardware.
    // Release has no fixture initializer or alternative audio implementation.
    init(model: AppModel, fixtureVoiceSession: VoiceConversationSession) {
        self.model = model
        _voiceSession = State(initialValue: fixtureVoiceSession)
    }
    #endif

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Group {
                    if workspaceSection == .chat { conversation }
                    else {
                        OrivynWorkspaceView(model: model, section: workspaceSection, openMenu: openHistory,
                            openChat: { navigate(to: .chat) }, openModels: { showModels = true })
                    }
                }
                    .disabled(showHistory)
                    .accessibilityHidden(showHistory)
                if showHistory {
                    HStack(spacing: 0) {
                        HistoryView(model: model, onClose: closeHistory,
                                    onSettings: { closeHistory(); showSettings = true },
                                    onModels: { closeHistory(); showModels = true },
                                    selectedSection: workspaceSection, onNavigate: navigate)
                            .frame(width: min(360, geometry.size.width * 0.84))
                        Button(action: closeHistory) {
                            Color.black.opacity(0.18).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close conversation history")
                        .accessibilityIdentifier("history.backdrop")
                        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                            if value.translation.width < -40 && abs(value.translation.height) < 70 { closeHistory() }
                        })
                    }
                    .frame(maxHeight: .infinity)
                    .background(alignment: .leading) { Color.evoSidebar.frame(width: min(360, geometry.size.width * 0.84)).ignoresSafeArea() }
                    .transition(.move(edge: .leading))
                    .zIndex(1)
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 25).onEnded { value in
                if !showHistory && value.startLocation.x < 28 && value.translation.width > 65 && abs(value.translation.height) < 70 { openHistory() }
            })
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: showHistory)
        }
        .safeAreaInset(edge: .top, spacing: 0) { incomingBanner }
        .sheet(item: $reviewingIncoming) { request in
            IncomingTextView(request: request, canAccept: canAcceptSharedText) { text in
                guard canAcceptSharedText else { throw IncomingTextError.composerBusy }
                guard incoming.pending?.id == request.id else { throw IncomingTextError.staleRequest }
                try model.acceptIncomingText(text)
                incoming.discard(id: request.id)
                reviewingIncoming = nil
                workspaceSection = .chat
                showHistory = false
            } cancel: {
                incoming.discard(id: request.id)
                reviewingIncoming = nil
            }
        }
        .sheet(item: $reviewingTool) { tool in
            NavigationStack {
                toolReview(tool)
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { reviewingTool = nil }.accessibilityIdentifier("tool.review.done")
                    } }
            }
        }
        .sheet(isPresented: $showModels) { ModelManagerView(model: model) }
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .sheet(item: $editingMessage) { editing in
            EditMessageView(message: editing.message) { text in
                await model.editAndBranch(messageID: editing.message.id, text: text, sourceConversationID: editing.conversationID)
            }
        }
        .sheet(item: $selectingText) { message in
            NavigationStack {
                ScrollView { Text(message.content).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                    .navigationTitle("Select text")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectingText = nil } } }
            }
        }
        .sheet(item: $pickerRequest) { request in
            switch request.kind {
            case .files:
                FileAttachmentPicker { result in
                    let accepted = pickerOwnership.consume(request, currentContext: model.attachmentImportContext)
                    finishPicker(request)
                    guard accepted else { return }
                    switch result {
                    case .success(let urls): Task { await model.addAttachments(from: urls, context: request.context) }
                    case .failure(let error): model.report(error)
                    }
                }
            case .photos:
                PhotoAttachmentPicker(selectionLimit: request.limit) { providers in
                    let accepted = pickerOwnership.consume(request, currentContext: model.attachmentImportContext)
                    finishPicker(request)
                    if accepted { importPhotos(providers, context: request.context) }
                }
            case .camera:
                CameraAttachmentPicker { result in
                    let accepted = pickerOwnership.consume(request, currentContext: model.attachmentImportContext)
                    finishPicker(request)
                    guard accepted else { return }
                    switch result {
                    case .success(let data):
                        if let data { Task { await model.addImageAttachment(data: data, suggestedName: "Camera photo.jpg", context: request.context) } }
                    case .failure(let error): model.report(error)
                    }
                }.ignoresSafeArea()
            }
        }
        .onChange(of: pickerRequest?.id) { oldID, newID in
            if let oldID, newID == nil { pickerOwnership.cancel(id: oldID) }
        }
        .sheet(item: $previewAttachment) { attachment in
            AttachmentPreviewView(attachment: attachment, originalURL: model.attachmentService.url(for: attachment), previewURL: model.attachmentService.previewURL(for: attachment))
        }
        .alert("Orivyn", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil; offersPrivacySettings = false }
            if offersPrivacySettings {
                Button("App Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    offersPrivacySettings = false
                }
            }
        } message: { Text(model.errorMessage ?? "") }
        .overlay(alignment: .top) {
            if copied { Text("Copied").font(.caption.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9).background(.regularMaterial, in: Capsule()).padding(.top, 6).transition(.opacity) }
        }
        .onAppear {
            model.setHeavyWorkForeground(scenePhase == .active)
            model.setHeavyWorkThermalState(ProcessInfo.processInfo.thermalState)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            model.handleLocalResourcePressure()
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            model.setHeavyWorkThermalState(ProcessInfo.processInfo.thermalState)
        }
        .onChange(of: scenePhase) { _, phase in
            model.setHeavyWorkForeground(phase == .active)
            ExternalWorkspaceController.shared.setForeground(phase == .active)
            model.plugins?.setForeground(phase == .active)
            if phase != .active { model.cancelAutomaticPreparation() }
            if phase == .background { voiceSession?.controller.setForeground(false); stopAudio(); cancelTransfers() }
            else if phase == .active { voiceSession?.controller.setForeground(true) }
        }
        .onChange(of: model.selectedConversationID) { oldID, newID in
            let ownVoiceSelection = voiceSession?.selectionChanged(from: oldID, to: newID) == true
            if !ownVoiceSelection { voice.stopRecording(); voice.stopSpeaking(); cancelTransfers() }
            followsTranscript = true
            userIsScrolling = false
            transcriptNearBottom = true
        }
        .onChange(of: model.selectedProviderID) { _, _ in stopAudio() }
        .onDisappear { model.cancelAutomaticPreparation(); stopAudio(); cancelTransfers() }
    }

    private var canAcceptSharedText: Bool {
        model.canAcceptIncomingText && !audioBusy && !attachmentsBusy
            && pickerRequest == nil && scenePhase == .active
    }
    private var canReviewSharedText: Bool {
        canAcceptSharedText && !showModels && !showSettings && !showHistory
            && editingMessage == nil && selectingText == nil && previewAttachment == nil
            && model.errorMessage == nil && reviewingTool == nil
    }
    @ViewBuilder private var incomingBanner: some View {
        if incoming.pending != nil || incoming.lastError != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let request = incoming.pending {
                    HStack {
                        Label("Shared text waiting", systemImage: "text.bubble").font(.subheadline)
                        Spacer()
                        Button("Review") { composerFocused = false; reviewingIncoming = request }
                            .disabled(!canReviewSharedText).accessibilityIdentifier("incoming.review")
                        Button { incoming.discard(id: request.id) } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Discard shared text")
                    }
                }
                if let error = incoming.lastError {
                    HStack(alignment: .top) {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Dismiss") { incoming.dismissError() }.font(.caption)
                    }
                }
            }
            .buttonStyle(.bordered).padding(.horizontal).padding(.vertical, 8)
            .background(.regularMaterial)
        }
    }

    private var conversation: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.activeConversation?.messages.isEmpty != false { welcome }
                else { transcript }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: openHistory) { EvoMenuGlyph().frame(width: 21, height: 21) }
                        .accessibilityLabel("Conversation history").accessibilityIdentifier("history.open")
                }
                ToolbarItem(placement: .principal) {
                    Button { prepareNavigation(); showModels = true } label: {
                        HStack(spacing: 5) {
                            Text("Orivyn").font(.system(.headline, design: .default)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain).accessibilityLabel("Choose model").accessibilityIdentifier("model.choose")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { prepareNavigation(); Task { await model.newConversation() } } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New conversation").accessibilityIdentifier("conversation.new")
                    Menu {
                        Button("Voice conversation", systemImage: "waveform") { startVoiceConversation() }
                            .accessibilityIdentifier("voice.start")
                        Button { prepareNavigation(); showModels = true } label: { Label("Models", systemImage: "cpu") }
                        Button { prepareNavigation(); showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                            .accessibilityIdentifier("settings.open")
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More options").accessibilityIdentifier("toolbar.more")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var welcome: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 30)
                    Text("What can I help with?")
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("welcome.title")
                    VStack(spacing: 10) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { planSuggestion; writeSuggestion }
                            VStack(spacing: 10) { planSuggestion; writeSuggestion }
                        }
                        suggestion("Explain something", icon: "lightbulb", prompt: "Explain this in simple terms: ", id: "suggestion.explain")
                    }
                    Spacer(minLength: 30)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var planSuggestion: some View {
        suggestion("Make a plan", icon: "list.bullet", prompt: "Help me make a practical plan for ", id: "suggestion.plan")
    }

    private var writeSuggestion: some View {
        suggestion("Help me write", icon: "pencil.line", prompt: "Help me write ", id: "suggestion.write")
    }

    private func suggestion(_ title: String, icon: String, prompt: String, id: String) -> some View {
        Button {
            // A queued action must recheck ownership, even after disabled styling.
            guard !audioBusy else { return }
            model.draft = prompt
            composerFocused = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(.subheadline).lineLimit(1).fixedSize()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }.buttonStyle(.plain).disabled(audioBusy).accessibilityIdentifier(id)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(model.activeConversation?.messages ?? []) { message in
                        MessageRow(message: message, isGenerating: model.isGenerating, isSpeaking: voice.isSpeaking,
                                   attachmentURL: { model.attachmentService.url(for: $0) },
                                   attachmentPreviewURL: { model.attachmentService.previewURL(for: $0) },
                                   onCopy: { copy(message.content) },
                                   onReadAloud: { readAloud(message.content) },
                                   onSelect: { selectingText = message },
                                   onEdit: { stopAudio(); if let id = model.selectedConversationID { editingMessage = EditingMessage(message: message, conversationID: id) } },
                                   onBranch: { stopAudio(); let origin = model.selectedConversationID; Task { await model.branch(through: message.id, sourceConversationID: origin) } },
                                   onRegenerate: { stopAudio(); followsTranscript = true; let origin = model.selectedConversationID; Task { await model.regenerate(messageID: message.id, sourceConversationID: origin) } })
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("conversation.bottom")
                }
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)
                .frame(maxWidth: 740).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("conversation.transcript")
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .alignment)
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, phase in
                userIsScrolling = phase == .interacting || phase == .decelerating
                if userIsScrolling { followsTranscript = transcriptNearBottom }
                else if phase == .idle { followsTranscript = transcriptNearBottom }
            }
            .onScrollGeometryChange(for: TranscriptGeometry.self) { geometry in
                TranscriptGeometry(height: geometry.contentSize.height, viewport: geometry.containerSize.height,
                                   bottomGap: geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height)
            } action: { old, new in
                transcriptNearBottom = new.bottomGap < 80
                if userIsScrolling { followsTranscript = transcriptNearBottom }
                else if followsTranscript && new.height > new.viewport && new.height > old.height {
                    proxy.scrollTo("conversation.bottom", anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !transcriptNearBottom {
                    Button {
                        followsTranscript = true
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("conversation.bottom", anchor: .bottom) }
                    } label: { Image(systemName: "arrow.down").frame(width: 44, height: 44).background(.regularMaterial, in: Circle()) }
                        .accessibilityLabel("Jump to latest message").accessibilityIdentifier("conversation.latest").padding()
                }
            }
        }
        // A new history needs its own initial layout even when it is shorter.
        // Same-history token updates retain identity and the reader's position.
        .id(model.selectedConversationID)
    }

    @ViewBuilder private func toolReview(_ tool: NativeToolSuggestion) -> some View {
        switch tool {
        case .email: MailDraftView()
        case .calendar: CalendarDraftView()
        case .browser: BrowserToolView()
        case .location: LocationToolView()
        case .reminder: ScheduledRemindersView()
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if model.isPreparingAutomaticModel {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.automaticDecision?.model.name ?? "Choosing a local model…").font(.caption.weight(.semibold))
                        Spacer()
                        Button("Cancel") { model.cancelAutomaticPreparation() }
                            .accessibilityIdentifier("model.automatic.cancel")
                    }
                    if let decision = model.automaticDecision {
                        Text(decision.reason).font(.caption).foregroundStyle(.secondary)
                        if decision.needsDownload {
                            Text("Download: \(decision.model.formattedSize). Your draft stays here until verification finishes.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let progress = model.downloadProgress { ProgressView(value: progress) }
                    else { ProgressView().controlSize(.mini) }
                }.padding(.horizontal, 24).accessibilityIdentifier("model.automatic.preparing")
            } else if !model.isGenerating && !audioBusy && !attachmentsBusy,
                      let suggestion = NativeToolSuggestion.forText(model.draft) {
                Button {
                    prepareNavigation()
                    reviewingTool = suggestion
                } label: {
                    Label("Review in \(suggestion.title)", systemImage: "arrow.up.forward.app")
                        .font(.subheadline)
                }.buttonStyle(.bordered).accessibilityIdentifier("tool.suggestion.\(suggestion.id)")
            }
            if let status = model.statusMessage {
                HStack {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.statusMessage = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Dismiss status")
                }.padding(.horizontal, 24)
            }
            if model.isGenerating && model.generatingConversationID != model.selectedConversationID {
                Text("A response is running in another conversation.").font(.caption).foregroundStyle(.secondary)
            }
            if let controller = voiceSession?.controller, controller.isActive || controller.state == .failed {
                voiceConversationControls(controller)
            } else if voice.isRecording || voice.isStarting || voice.isFinishing {
                HStack {
                    if voice.isStarting || voice.isFinishing { ProgressView().controlSize(.mini) }
                    Text(voice.isStarting ? "Requesting microphone…" : voice.isFinishing ? "Finishing dictation…" : "Listening on this iPhone…")
                    Spacer()
                    if voice.isRecording { Button("Done") { voice.finishRecording() }.accessibilityIdentifier("dictation.done") }
                    Button("Cancel") { stopAudio() }.accessibilityIdentifier("dictation.cancel")
                }.font(.caption).padding(.horizontal, 24)
            }
            if attachmentsBusy {
                HStack {
                    ProgressView().controlSize(.mini)
                    Text("Importing and recognizing text…")
                    Spacer()
                    Button("Cancel") { cancelTransfers() }.accessibilityIdentifier("attachment.import.cancel")
                }.font(.caption).padding(.horizontal, 24).accessibilityIdentifier("attachment.import.progress")
            }
            if !model.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.pendingAttachments) { attachment in
                            AttachmentTile(attachment: attachment, previewURL: model.attachmentService.previewURL(for: attachment),
                                           open: { previewAttachment = attachment }, remove: { model.removePendingAttachment(attachment) })
                        }
                    }.padding(.horizontal, 24)
                }
            }
            HStack(alignment: .bottom, spacing: 0) {
                Menu {
                    Button("Choose files", systemImage: "folder") { prepareAttachmentPicker(.files) }
                        .accessibilityIdentifier("attachment.files")
                    Button("Choose photos", systemImage: "photo") { prepareAttachmentPicker(.photos) }
                        .accessibilityIdentifier("attachment.photos")
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take photo", systemImage: "camera") { openCamera() }.accessibilityIdentifier("attachment.camera")
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 22, weight: .regular)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Attach files or photos").accessibilityIdentifier("composer.attach")
                .disabled(model.availableAttachmentSlots == 0 || attachmentsBusy || audioBusy)
                ZStack(alignment: .topLeading) {
                    if model.draft.isEmpty {
                        Text("Ask Orivyn").font(.body).foregroundStyle(.secondary)
                            .padding(.top, 8).padding(.leading, 5).accessibilityHidden(true)
                    }
                    TextEditor(text: $model.draft)
                        .font(.body).scrollContentBackground(.hidden)
                        .frame(height: composerHeight)
                        .focused($composerFocused)
                        .disabled(audioBusy)
                        .accessibilityLabel("Message Orivyn").accessibilityIdentifier("composer.input")
                }
                Button { toggleDictation() } label: {
                    Image(systemName: voice.isRecording ? "mic.fill" : "mic").font(.system(size: 20)).frame(width: 44, height: 44)
                }
                .accessibilityLabel(voice.isRecording ? "Finish dictation" : "Dictate message")
                .accessibilityIdentifier("composer.dictate").disabled(voice.isStarting || voice.isFinishing || voiceSession?.controller.isActive == true || attachmentsBusy)
                if model.isGenerating {
                    Button { if voiceSession?.controller.isActive == true { voiceSession?.stop() } else { model.stop() } } label: {
                        Image(systemName: "stop.fill").font(.system(size: 13)).foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 32, height: 32).background(Color.primary, in: Circle()).frame(width: 44, height: 44)
                    }.accessibilityLabel("Stop response").accessibilityIdentifier("composer.stop")
                } else if model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.pendingAttachments.isEmpty {
                    Button { startVoiceConversation() } label: {
                        Image(systemName: "waveform").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 32, height: 32).background(Color.primary, in: Circle()).frame(width: 44, height: 44)
                    }.accessibilityLabel("Start voice conversation").accessibilityIdentifier("composer.voice").disabled(audioBusy || attachmentsBusy)
                } else {
                    Button { stopAudio(); followsTranscript = true; model.send(); composerFocused = false } label: {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 32, height: 32).background(model.canSend ? Color.primary : Color.secondary.opacity(0.25), in: Circle()).frame(width: 44, height: 44)
                    }.disabled(!model.canSend || audioBusy || attachmentsBusy).accessibilityLabel("Send message").accessibilityIdentifier("composer.send")
                }
            }
            .buttonStyle(.plain)
            .padding(4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.06), radius: 12, y: 3)
            .padding(.horizontal, 30)
            if model.network.isOnline == false {
                Text("Offline · on-device models work when installed")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12).padding(.bottom, 10)
        .background { LinearGradient(colors: [Color(uiColor: .systemBackground).opacity(0), Color(uiColor: .systemBackground)], startPoint: .top, endPoint: .bottom) }
    }

    private var composerHeight: CGFloat {
        let charactersPerLine = dynamicTypeSize.isAccessibilitySize ? 12 : 25
        let lines = model.draft.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, ($1.count + charactersPerLine - 1) / charactersPerLine) }
        return min(150, max(40, CGFloat(lines) * inputLineHeight + 16))
    }

    private var attachmentsBusy: Bool { transferID != nil || model.isImportingAttachments }
    private var audioBusy: Bool { voice.isStarting || voice.isRecording || voice.isFinishing || voiceSession?.controller.isActive == true }

    private func prepareNavigation() { model.cancelAutomaticPreparation(); composerFocused = false; stopAudio(); cancelTransfers() }
    private func navigate(to section: WorkspaceSection) { prepareNavigation(); workspaceSection = section; showHistory = false }
    private func openHistory() { prepareNavigation(); showHistory = true }
    private func closeHistory() { showHistory = false }

    private func stopAudio() {
        dictationTask?.cancel()
        dictationTask = nil
        dictationID = nil
        voiceSession?.stop()
        voice.stopRecording()
        voice.stopSpeaking()
    }

    private func startVoiceConversation() {
        model.cancelAutomaticPreparation()
        guard !attachmentsBusy, model.pendingAttachments.isEmpty else {
            model.errorMessage = "Voice conversation cannot send pending files. Your files are kept. Send or remove them, and finish or cancel importing, before starting voice."
            return
        }
        stopAudio()
        composerFocused = false
        followsTranscript = true
        let session = VoiceConversationSession(model: model, audio: voice)
        session.controller.onError = { message in offersPrivacySettings = true; model.errorMessage = message }
        voiceSession = session
        do { try session.start() }
        catch { model.report(error) }
    }

    private func toggleDictation() {
        model.cancelAutomaticPreparation()
        if voice.isRecording { voice.finishRecording(); return }
        guard !voice.isStarting, !voice.isFinishing else { return }
        stopAudio()
        dictationPrefix = model.draft.isEmpty ? "" : model.draft + " "
        voice.onTranscript = { text in model.draft = dictationPrefix + text }
        voice.onFinalTranscript = { text in model.draft = dictationPrefix + text }
        voice.onError = { offersPrivacySettings = true; model.errorMessage = $0 }
        voice.onInterruption = { model.errorMessage = "Dictation was interrupted. Your draft is kept." }
        let id = UUID()
        dictationID = id
        dictationTask = Task { @MainActor in
            guard !Task.isCancelled, dictationID == id else { return }
            defer { if dictationID == id { dictationTask = nil } }
            do { try await voice.startRecording() }
            catch { if !Task.isCancelled, dictationID == id { offersPrivacySettings = true; model.report(error) } }
        }
    }

    private func readAloud(_ text: String) {
        let wasSpeaking = voice.isSpeaking
        stopAudio()
        if !wasSpeaking { do { try voice.speak(text) } catch { model.report(error) } }
    }

    private func prepareAttachmentPicker(_ kind: AttachmentPickerRequest.Kind) {
        model.cancelAutomaticPreparation()
        stopAudio()
        composerFocused = false
        let request = AttachmentPickerRequest(context: model.attachmentImportContext, kind: kind, limit: max(1, model.availableAttachmentSlots))
        pickerOwnership.open(request)
        pickerRequest = request
    }

    private func finishPicker(_ request: AttachmentPickerRequest) {
        if pickerRequest?.id == request.id { pickerRequest = nil }
    }

    private func openCamera() {
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        guard authorization != .denied && authorization != .restricted else {
            offersPrivacySettings = true
            model.errorMessage = "Camera access is unavailable. You can choose a photo or enable camera access in App Settings."
            return
        }
        prepareAttachmentPicker(.camera)
    }

    private func importPhotos(_ providers: [NSItemProvider], context: UUID) {
        guard !providers.isEmpty, context == model.attachmentImportContext else { return }
        transferTask?.cancel()
        let id = UUID()
        transferID = id
        transferTask = Task { @MainActor in
            defer { if transferID == id { transferID = nil; transferTask = nil } }
            do {
                for provider in providers {
                    try Task.checkCancellation()
                    guard transferID == id, context == model.attachmentImportContext else { return }
                    let image = try await PickedImage.load(from: provider)
                    try Task.checkCancellation()
                    guard transferID == id, context == model.attachmentImportContext else { return }
                    await model.addImageAttachment(data: image.data, suggestedName: image.name, context: context)
                }
            } catch is CancellationError { }
            catch { if transferID == id && context == model.attachmentImportContext { model.report(error) } }
        }
    }

    private func cancelTransfers() {
        transferTask?.cancel()
        transferTask = nil
        transferID = nil
        if let request = pickerRequest { pickerOwnership.cancel(id: request.id) }
        pickerRequest = nil
        model.cancelAttachmentImports()
    }

    @ViewBuilder private func voiceConversationControls(_ controller: VoiceConversationController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if controller.state == .requestingPermission || controller.state == .finishing || controller.state == .awaitingResponse {
                    ProgressView().controlSize(.mini)
                } else { Image(systemName: controller.state == .speaking ? "speaker.wave.2" : "waveform") }
                Text(voiceStatus(controller.state)).font(.subheadline.weight(.medium))
                Spacer()
                Button("End") { voiceSession?.stop() }.accessibilityIdentifier("voice.end")
            }
            if controller.state == .listening {
                Button("Send spoken turn") { controller.finishTurn() }.accessibilityIdentifier("voice.finish")
            } else if controller.state == .speaking || controller.state == .awaitingResponse {
                Button("Interrupt and speak") { controller.interruptAndListen() }.accessibilityIdentifier("voice.interrupt")
            }
            Text("Foreground only. Speech is transcribed on this iPhone. Tap to interrupt; the microphone is off during playback.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 24).accessibilityIdentifier("voice.status")
    }

    private func voiceStatus(_ state: VoiceConversationController.State) -> String {
        switch state {
        case .idle: "Voice stopped"
        case .requestingPermission: "Preparing microphone…"
        case .listening: "Listening…"
        case .finishing: "Finishing your words…"
        case .awaitingResponse: "Waiting for the model…"
        case .speaking: "Speaking…"
        case .failed: "Voice stopped. Your draft is kept."
        }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        withAnimation { copied = true }
        Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { copied = false } }
    }
}

private struct TranscriptGeometry: Equatable {
    let height: CGFloat
    let viewport: CGFloat
    let bottomGap: CGFloat
}

/// Drawn locally as an original-color image so toolbar template tint does not
/// turn these custom strokes into low-contrast material decoration.
struct EvoMenuGlyph: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Image(uiImage: Self.image(dark: scheme == .dark)).renderingMode(.original) }
    static func image(dark: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 21, height: 21)).image { context in
            let cg = context.cgContext
            cg.setStrokeColor((dark ? UIColor.white : UIColor.black).cgColor)
            cg.setLineWidth(1.7)
            cg.setLineCap(.round)
            cg.move(to: CGPoint(x: 2, y: 7)); cg.addLine(to: CGPoint(x: 19, y: 7))
            cg.move(to: CGPoint(x: 2, y: 14)); cg.addLine(to: CGPoint(x: 12, y: 14))
            cg.strokePath()
        }
    }
}
