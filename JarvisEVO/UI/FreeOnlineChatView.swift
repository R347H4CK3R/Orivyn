import SwiftUI

/// Separate, temporary single-turn surface. It receives no saved chat or attachment context.
struct FreeOnlineChatView: View {
    @Bindable var state: FreeOnlineChatState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @State private var purpose = "All"
    @State private var proposedModel: OpenRouterFreeModel?
    @State private var didRefresh = false
    @State private var proposedAuto = false

    private var matches: [OpenRouterFreeModel] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.models.filter { model in
            (purpose == "All" || model.suggestedUses.contains { $0.rawValue == purpose }) &&
            model.matchesSearch(text)
        }
    }
    private var canSend: Bool {
        state.hasConsented && !state.isSending && !state.isLoadingCatalog &&
        !state.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Needs internet · Free usage limits apply", systemImage: "network")
                        .font(.headline)
                    Text(FreeOnlineChatState.disclosure).font(.subheadline)
                        .accessibilityIdentifier("freeOnline.disclosure")
                    Text("No paid fallback. Availability and free pricing are checked again before each message.")
                        .font(.subheadline)
                    Text("One message at a time. This temporary reply is not added to your saved chats. Each send starts fresh, without earlier questions or replies.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Choose how to chat") {
                    Button { proposedAuto = true } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Auto · Recommended", systemImage: "sparkles").font(.headline)
                            Text("Chooses a currently free AI for the new text you type. The choice is made on your iPhone, not by another online service.")
                                .font(.subheadline).foregroundStyle(.primary)
                            Text(state.usesAutomaticSelection ? "Your default choice" : "Switch back to Auto")
                                .font(.subheadline.weight(.semibold))
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 8)
                    }
                    .tint(.teal)
                    .disabled(state.isSending || state.isLoadingCatalog)
                    .accessibilityIdentifier("freeOnline.auto")
                    Text("Auto is a simple task-fit suggestion, not a guarantee of the best answer. Manual choice is optional below.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Manual choice · Optional") {
                    Button {
                        didRefresh = true
                        proposedModel = nil
                        Task { await state.refreshCatalog() }
                    } label: {
                        Label(didRefresh ? "Refresh free choices" : "Check free choices", systemImage: "arrow.clockwise")
                            .frame(minHeight: 44)
                    }
                    .disabled(state.isLoadingCatalog || state.isSending)
                    .accessibilityIdentifier("freeOnline.refresh")
                    if state.isLoadingCatalog { ProgressView("Checking current free choices…") }
                    if !state.models.isEmpty {
                        TextField("Search names or tasks", text: $query)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityIdentifier("freeOnline.search")
                        Picker("Good for", selection: $purpose) {
                            Text("All").tag("All")
                            ForEach(OpenRouterFreeModel.SuggestedUse.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        ForEach(matches) { model in
                            Button { proposedModel = model } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.name).font(.headline).foregroundStyle(.primary)
                                    Text(model.shortDescription).font(.subheadline).foregroundStyle(.secondary)
                                    Text(state.selectedModelID == model.id ? "Selected for this session" : "Review and choose")
                                        .font(.subheadline.weight(.semibold))
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 6)
                            }
                            .disabled(state.isSending || state.isLoadingCatalog)
                            .accessibilityIdentifier("freeOnline.model.\(model.id)")
                        }
                        if matches.isEmpty { Text("No matches. Try another name or task.") }
                    } else if didRefresh && !state.isLoadingCatalog && state.errorMessage == nil {
                        Text("No free choices are verified right now. Try later or return to offline chat.")
                    }
                }
                if state.hasConsented {
                    Section("Your connection") {
                        SecureField("OpenRouter API key", text: $state.apiKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .disabled(state.isSending)
                            .accessibilityIdentifier("freeOnline.key")
                        Text("An API key is your private connection code from OpenRouter. It is used only for this session, never saved here. Do not send it in a message. You do not need to buy credits for this free-only mode.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Link("Open OpenRouter to manage your own key", destination: URL(string: "https://openrouter.ai/settings/keys")!)
                            .frame(minHeight: 44)
                    }
                    Section("New online message") {
                        Text(state.usesAutomaticSelection ? "Auto chooses a verified free model when you send." : "Manual choice: " + (state.models.first(where: { $0.id == state.selectedModelID })?.name ?? "Refresh choices"))
                            .font(.subheadline.weight(.semibold))
                        Text("Only what you type below will be sent. Your offline draft stays separate.")
                            .font(.subheadline)
                        TextEditor(text: $state.draft)
                            .frame(minHeight: 120).disabled(state.isSending)
                            .accessibilityLabel("New online message")
                            .accessibilityIdentifier("freeOnline.input")
                        if state.isSending {
                            ProgressView("Waiting for your online reply…")
                            Button("Cancel request") { state.cancel() }
                                .frame(minHeight: 44).accessibilityIdentifier("freeOnline.cancel")
                        } else {
                            Button { Task { await state.send() } } label: {
                                Label("Send this message online", systemImage: "arrow.up.circle.fill").frame(minHeight: 44)
                            }
                            .disabled(!canSend).accessibilityIdentifier("freeOnline.send")
                        }
                    }
                }
                if let error = state.errorMessage {
                    Section("Couldn’t finish") {
                        Text(error).accessibilityIdentifier("freeOnline.error")
                    }
                }
                if let response = state.response {
                    Section("Online reply") {
                        if let name = state.lastResponseModelName {
                            Text("Answered by " + name).font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier("freeOnline.actualModel")
                        }
                        Text(response).textSelection(.enabled).accessibilityIdentifier("freeOnline.response")
                        Text("Copy anything you want to keep before leaving. AI answers can be wrong.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Free online").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Back to offline") { state.returnToOffline(); dismiss() }
                        .accessibilityIdentifier("freeOnline.close")
                }
            }
            .confirmationDialog("Use Auto online?", isPresented: $proposedAuto, titleVisibility: .visible) {
                Button("Use Free Online") { state.useFreeOnlineAuto(); proposedAuto = false }
                Button("Cancel", role: .cancel) { proposedAuto = false }
            } message: {
                Text("Auto chooses one currently verified free model for each new message.\n\n" + FreeOnlineChatState.disclosure)
            }
            .confirmationDialog("Use this AI online?", isPresented: Binding(get: { proposedModel != nil }, set: { if !$0 { proposedModel = nil } }), titleVisibility: .visible, presenting: proposedModel) { choice in
                Button("Use Free Online") {
                    state.useFreeOnline(modelID: choice.id)
                    proposedModel = nil
                }
                Button("Cancel", role: .cancel) { proposedModel = nil }
            } message: { choice in
                Text("\(choice.name)\n\n" + FreeOnlineChatState.disclosure)
            }
        }
        .onDisappear { state.returnToOffline() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { proposedAuto = false; proposedModel = nil; didRefresh = false; state.returnToOffline() }
        }
    }
}
