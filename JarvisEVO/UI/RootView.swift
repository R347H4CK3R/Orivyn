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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.activeConversation?.messages.isEmpty != false { welcome }
                else { transcript }
            }
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { composerFocused = false; showHistory = true } label: { Image(systemName: "sidebar.left") }
                        .accessibilityLabel("Conversation history").accessibilityIdentifier("history.open")
                }
                ToolbarItem(placement: .principal) {
                    Button { composerFocused = false; showModels = true } label: {
                        VStack(spacing: 3) {
                            HStack(spacing: 5) {
                                Text("Jarvis-EVO").font(.headline)
                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                            }
                            Text(model.selectedProvider?.title ?? "Choose a model").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain).accessibilityLabel("Choose model").accessibilityIdentifier("model.choose")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { composerFocused = false; showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Settings").accessibilityIdentifier("settings.open")
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showHistory) { HistoryView(model: model) }
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
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Spacer(minLength: 50)
                EvoMark(size: 52)
                VStack(alignment: .leading, spacing: 12) {
                    Text("What’s on\nyour mind?").font(.system(size: 36, weight: .semibold, design: .rounded)).tracking(-1)
                    Text("A space to think, make, and figure things out.")
                        .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 10) {
                    suggestion("Make a plan", subtitle: "Turn an idea into a clear next step", icon: "list.bullet.rectangle", prompt: "Help me make a practical plan for ", id: "suggestion.plan")
                    suggestion("Find the words", subtitle: "Draft something that sounds like you", icon: "square.and.pencil", prompt: "Help me write ", id: "suggestion.write")
                    suggestion("Understand something", subtitle: "Start with a simpler explanation", icon: "lightbulb", prompt: "Explain this in simple terms: ", id: "suggestion.explain")
                }
                if model.selectedProvider?.isAvailable != true {
                    Button { showModels = true } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "iphone.and.arrow.down").padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bring a model on board").font(.subheadline.weight(.medium))
                                Text("Download once, then chat privately offline.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(14).background(Color.evoAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
    }

    private func suggestion(_ title: String, subtitle: String, icon: String, prompt: String, id: String) -> some View {
        Button { model.draft = prompt; composerFocused = true } label: {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 19, weight: .regular)).frame(width: 24).foregroundStyle(Color.evoAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.tertiary)
            }.padding(16).background(Color.evoSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 17))
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
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 10)
                .frame(maxWidth: 740).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.activeConversation?.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("conversation.bottom", anchor: .bottom) }
            }
            .onChange(of: model.selectedConversationID) { _, _ in proxy.scrollTo("conversation.bottom", anchor: .bottom) }
        }
    }

    private var composer: some View {
        VStack(spacing: 9) {
            if let status = model.statusMessage {
                HStack {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.statusMessage = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Dismiss status")
                }.padding(.horizontal, 20)
            }
            if model.isGenerating && model.generatingConversationID != model.selectedConversationID {
                Text("A response is running in another conversation.").font(.caption).foregroundStyle(.secondary)
            }
            if voice.isRecording {
                HStack {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative)
                    Text("Listening on this iPhone…")
                    Spacer()
                    Button("Done") { voice.stopRecording() }
                }.font(.caption).foregroundStyle(Color.evoAccent).padding(.horizontal, 20)
            }
            if !model.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.pendingAttachments) { attachment in
                            HStack(spacing: 7) {
                                Image(systemName: "doc.text")
                                Text(attachment.name).lineLimit(1).frame(maxWidth: 180)
                                Button { model.removePendingAttachment(attachment) } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Remove \(attachment.name)")
                            }.font(.caption).padding(10).background(Color.evoSurface, in: Capsule())
                        }
                    }.padding(.horizontal, 16)
                }
            }
            VStack(spacing: 2) {
                ZStack(alignment: .topLeading) {
                    if model.draft.isEmpty { Text("Message Jarvis-EVO").foregroundStyle(.tertiary).padding(.top, 12).padding(.leading, 5).accessibilityHidden(true) }
                    TextEditor(text: $model.draft)
                        .font(.body).scrollContentBackground(.hidden)
                        .frame(height: composerHeight)
                        .focused($composerFocused)
                        .accessibilityLabel("Message Jarvis-EVO").accessibilityIdentifier("composer.input")
                }.padding(.horizontal, 12).padding(.top, 3)
                HStack(spacing: 16) {
                    Button { composerFocused = false; showAttachmentImporter = true } label: { Image(systemName: "plus").font(.system(size: 20, weight: .regular)).frame(width: 36, height: 36) }
                        .accessibilityLabel("Attach PDF or text file").accessibilityIdentifier("composer.attach")
                        .disabled(model.pendingAttachments.count >= 4)
                    Spacer()
                    Button { toggleDictation() } label: {
                        Image(systemName: voice.isRecording ? "mic.fill" : "mic").font(.system(size: 19)).frame(width: 36, height: 36)
                    }.foregroundStyle(voice.isRecording ? Color.evoAccent : Color.primary).accessibilityLabel(voice.isRecording ? "Stop dictation" : "Dictate message").disabled(voice.isStarting)
                    if model.isGenerating {
                        Button { model.stop() } label: {
                            Image(systemName: "stop.fill").font(.system(size: 13)).foregroundStyle(Color(uiColor: .systemBackground)).frame(width: 36, height: 36).background(Color.primary, in: Circle())
                        }.accessibilityLabel("Stop response").accessibilityIdentifier("composer.stop")
                    } else {
                        Button { voice.stopRecording(); model.send(); composerFocused = false } label: {
                            Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(uiColor: .systemBackground)).frame(width: 36, height: 36).background(model.canSend ? Color.primary : Color.secondary.opacity(0.35), in: Circle())
                        }.disabled(!model.canSend).accessibilityLabel("Send message").accessibilityIdentifier("composer.send")
                    }
                }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 9)
            }
            .background(Color.evoSurface, in: RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(Color.primary.opacity(0.04), lineWidth: 1))
            .padding(.horizontal, 14)
            Text(model.network.isOnline == false ? "Offline · on-device models available if installed" : model.selectedProviderID == "remote" ? "Remote model · check important information" : "Private by default · check important information")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 3)
        }
        .padding(.top, 9).background(.background)
    }

    private var composerHeight: CGFloat { min(118, max(44, CGFloat(model.draft.count / 38 + model.draft.filter { $0 == "\n" }.count + 1) * 23 + 10)) }

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
