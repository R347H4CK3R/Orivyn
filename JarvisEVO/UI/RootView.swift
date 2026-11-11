import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: AppModel
    @State private var voice = VoiceService()
    @State private var showHistory = false
    @State private var showModels = false
    @State private var showSettings = false
    @State private var showAttachmentImporter = false
    @State private var editingMessage: ChatMessage?
    @State private var selectingText: ChatMessage?
    @State private var copied = false
    @State private var dictationPrefix = ""
    @FocusState private var composerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var inputLineHeight: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                conversation
                    .disabled(showHistory)
                    .accessibilityHidden(showHistory)
                if showHistory {
                    HStack(spacing: 0) {
                        HistoryView(model: model, onClose: closeHistory,
                                    onSettings: { closeHistory(); showSettings = true },
                                    onModels: { closeHistory(); showModels = true })
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
        .sheet(isPresented: $showModels) { ModelManagerView(model: model) }
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .sheet(item: $editingMessage) { message in
            EditMessageView(message: message) { text in
                Task { await model.editAndBranch(messageID: message.id, text: text) }
            }
        }
        .sheet(item: $selectingText) { message in
            NavigationStack {
                ScrollView { Text(message.content).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                    .navigationTitle("Select text")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectingText = nil } } }
            }
        }
        .fileImporter(isPresented: $showAttachmentImporter, allowedContentTypes: [.pdf, .plainText, .json, .sourceCode], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await model.addAttachments(from: urls) }
            case .failure(let error): model.report(error)
            }
        }
        .alert("Jarvis-EVO", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .overlay(alignment: .top) {
            if copied { Text("Copied").font(.caption.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9).background(.regularMaterial, in: Capsule()).padding(.top, 6).transition(.opacity) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { voice.stopRecording() } }
        .onChange(of: model.selectedConversationID) { _, _ in voice.stopRecording() }
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
                    Button { composerFocused = false; showModels = true } label: {
                        HStack(spacing: 5) {
                            Text("Jarvis-EVO").font(.system(.headline, design: .default)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain).accessibilityLabel("Choose model").accessibilityIdentifier("model.choose")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { composerFocused = false; Task { await model.newConversation() } } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New conversation").accessibilityIdentifier("conversation.new")
                    Menu {
                        Button { composerFocused = false; showModels = true } label: { Label("Models", systemImage: "cpu") }
                        Button { composerFocused = false; showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
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
        Button { model.draft = prompt; composerFocused = true } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(.subheadline).lineLimit(1).fixedSize()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(model.activeConversation?.messages ?? []) { message in
                        MessageRow(message: message, isGenerating: model.isGenerating, isSpeaking: voice.isSpeaking,
                                   attachmentURL: { model.attachmentService.url(for: $0) },
                                   onCopy: { copy(message.content) },
                                   onReadAloud: { if voice.isSpeaking { voice.stopSpeaking() } else { do { try voice.speak(message.content) } catch { model.report(error) } } },
                                   onSelect: { selectingText = message },
                                   onEdit: { editingMessage = message },
                                   onBranch: { Task { await model.branch(through: message.id) } },
                                   onRegenerate: { Task { await model.regenerate(messageID: message.id) } })
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("conversation.bottom")
                }
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)
                .frame(maxWidth: 740).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.activeConversation?.messages.count) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("conversation.bottom", anchor: .bottom) }
            }
            .onChange(of: model.selectedConversationID) { _, _ in proxy.scrollTo("conversation.bottom", anchor: .bottom) }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
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
            if voice.isRecording {
                HStack {
                    Image(systemName: "waveform")
                    Text("Listening on this iPhone…")
                    Spacer()
                    Button("Done") { voice.stopRecording() }
                }.font(.caption).padding(.horizontal, 24)
            }
            if !model.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.pendingAttachments) { attachment in
                            HStack(spacing: 7) {
                                Image(systemName: "doc.text")
                                Text(attachment.name).lineLimit(1).frame(maxWidth: 180)
                                Button { model.removePendingAttachment(attachment) } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Remove \(attachment.name)")
                            }.font(.caption).padding(10).background(Color.evoSurface, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }.padding(.horizontal, 24)
                }
            }
            HStack(alignment: .bottom, spacing: 0) {
                Button { composerFocused = false; showAttachmentImporter = true } label: {
                    Image(systemName: "plus").font(.system(size: 22, weight: .regular)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Attach PDF or text file").accessibilityIdentifier("composer.attach")
                .disabled(model.pendingAttachments.count >= 4)
                ZStack(alignment: .topLeading) {
                    if model.draft.isEmpty {
                        Text("Ask Jarvis-EVO").font(.body).foregroundStyle(.secondary)
                            .padding(.top, 8).padding(.leading, 5).accessibilityHidden(true)
                    }
                    TextEditor(text: $model.draft)
                        .font(.body).scrollContentBackground(.hidden)
                        .frame(height: composerHeight)
                        .focused($composerFocused)
                        .accessibilityLabel("Message Jarvis-EVO").accessibilityIdentifier("composer.input")
                }
                Button { toggleDictation() } label: {
                    Image(systemName: voice.isRecording ? "mic.fill" : "mic").font(.system(size: 20)).frame(width: 44, height: 44)
                }
                .accessibilityLabel(voice.isRecording ? "Stop dictation" : "Dictate message")
                .accessibilityIdentifier("composer.dictate").disabled(voice.isStarting)
                if model.isGenerating {
                    Button { model.stop() } label: {
                        Image(systemName: "stop.fill").font(.system(size: 13)).foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 32, height: 32).background(Color.primary, in: Circle()).frame(width: 44, height: 44)
                    }.accessibilityLabel("Stop response").accessibilityIdentifier("composer.stop")
                } else {
                    Button { voice.stopRecording(); model.send(); composerFocused = false } label: {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(uiColor: .systemBackground))
                            .frame(width: 32, height: 32).background(model.canSend ? Color.primary : Color.secondary.opacity(0.25), in: Circle()).frame(width: 44, height: 44)
                    }.disabled(!model.canSend).accessibilityLabel("Send message").accessibilityIdentifier("composer.send")
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

    private func openHistory() { composerFocused = false; showHistory = true }
    private func closeHistory() { showHistory = false }

    private func toggleDictation() {
        if voice.isRecording { voice.stopRecording(); return }
        dictationPrefix = model.draft.isEmpty ? "" : model.draft + " "
        voice.onTranscript = { text in model.draft = dictationPrefix + text }
        voice.onError = { model.errorMessage = $0 }
        Task { do { try await voice.startRecording() } catch { model.report(error) } }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        withAnimation { copied = true }
        Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { copied = false } }
    }
}

/// Original two-stroke navigation glyph, not a copied brand asset.
private struct EvoMenuGlyph: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().frame(width: 18, height: 1.7)
            Capsule().frame(width: 11, height: 1.7)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
