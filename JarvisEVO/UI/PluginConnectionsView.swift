import SwiftUI

struct PluginConnectionsSection: View {
    @Bindable var broker: PluginBroker
    var model: AppModel? = nil
    let onAdd: () -> Void
    let onConnect: (PluginConnectionRecord) -> Void
    let onRemove: (PluginConnectionRecord) -> Void
    var body: some View {
        Section {
            if broker.journal.requiresRecovery {
                Text(PluginExecutionError.outcomeNotRecorded.localizedDescription)
                    .font(.footnote).foregroundStyle(.red).accessibilityIdentifier("plugin.recovery")
            }
            Button("Add plugin connection", systemImage: "plus.circle", action: onAdd)
                .accessibilityIdentifier("plugin.add").disabled(broker.isBusy)
            Text("Connect your own HTTPS MCP server. No plugin code is installed on iOS. External providers may charge; Orivyn does not supply a hosted computer or forward your chats automatically.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(broker.connections) { record in
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.name).font(.headline)
                    Text(record.endpoint).font(.caption).foregroundStyle(.secondary)
                    if broker.activeConnection?.id == record.id && broker.canReviewTools {
                        Text("Connected · catalog reviewed").font(.caption).accessibilityIdentifier("plugin.connected")
                        if let model {
                            NavigationLink("Describe a task") { PluginTaskProposalView(broker: broker, model: model) }
                        }
                        ForEach(broker.tools) { tool in
                            NavigationLink(tool.title ?? tool.name) { PluginToolCallView(broker: broker, tool: tool) }
                        }
                        Button("Disconnect") { broker.disconnect() }
                    } else {
                        Button("Connect and review tools") { onConnect(record) }.disabled(broker.isBusy)
                    }
                    Button("Remove saved connection", role: .destructive) { onRemove(record) }.disabled(broker.isBusy)
                }.padding(.vertical, 5)
            }
            NavigationLink("Execution log") { PluginExecutionLogView(journal: broker.journal) }
        } header: { Text("Remote plugins") }
        .buttonStyle(.borderless)
    }
}

struct PluginConnectionPresentation: Identifiable {
    let id = UUID()
    var saved: PluginConnectionRecord?
}

struct PluginConnectionForm: View {
    @Bindable var broker: PluginBroker
    var saved: PluginConnectionRecord?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var endpoint = ""
    @State private var token = ""
    @State private var useSaved = false
    @State private var remember = false
    @State private var didInstall = false
    @State private var error: String?
    @State private var connectionTask: Task<Void, Never>?
    @State private var connectionAttempt: UUID?
    private var validEndpoint: Bool { (try? MCPEndpoint.validated(endpoint)) != nil }
    var body: some View {
        NavigationStack {
            Form {
                Section("Server you choose") {
                    TextField("https://server.example/mcp", text: $endpoint)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityIdentifier("plugin.endpoint")
                    SecureField("Bearer token (optional)", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if saved?.hasSavedToken == true { Toggle("Use token saved for this endpoint", isOn: $useSaved) }
                    Toggle("Remember this token on this iPhone", isOn: $remember)
                    Text("Connect sends the MCP handshake and optional token only to this exact endpoint. Use a server you trust. Tokens are not given to Jarvis. Remember saves in device-only Keychain only when you install; otherwise disconnecting clears the in-memory credential.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.disabled(broker.isBusy || broker.stagedConnection != nil)
                Section {
                    Button("Connect and inspect tools") {
                        error = nil
                        let submittedEndpoint = endpoint, submittedToken = token, submittedSaved = useSaved
                        let attempt = UUID(); connectionAttempt = attempt
                        connectionTask = Task {
                            do { try await broker.connect(endpointText: submittedEndpoint, token: submittedToken, useSavedToken: submittedSaved) }
                            catch { if connectionAttempt == attempt && !Task.isCancelled { self.error = error.localizedDescription } }
                            if connectionAttempt == attempt { connectionTask = nil; connectionAttempt = nil }
                        }
                    }.disabled(!validEndpoint || connectionTask != nil || broker.isBusy || broker.stagedConnection != nil)
                        .accessibilityIdentifier("plugin.connect")
                    if broker.isBusy { ProgressView("Connecting…") }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                if let staged = broker.stagedConnection {
                    Section("Inspect before installing") {
                        Text(staged.name).font(.headline)
                        Text("Server version: \(staged.version)").font(.caption)
                        Text(staged.endpoint).font(.caption)
                        Text("\(broker.tools.count) tools. Server names, descriptions and read-only hints are untrusted claims, not permission. Each call still needs your review; nothing has run.").font(.footnote)
                        ForEach(broker.tools) { tool in
                            DisclosureGroup(tool.name) {
                                if let description = tool.description { Text(description).font(.footnote) }
                                Text(pluginJSON(tool.inputSchema.json)).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                        Button("Install reviewed connection") {
                            do { try broker.installConnection(rememberToken: remember); token = ""; didInstall = true; dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("plugin.install")
                    }
                }
                Section("Compatibility") {
                    Text("MCP 2025-06-18, bounded tools and JSON/finite SSE responses only. OAuth login, interactive server requests and a universal plugin store are not supported. No real external provider has been verified for this candidate yet.").font(.footnote)
                }
            }.navigationTitle("Add plugin").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelConnection(); dismiss() }.accessibilityIdentifier("plugin.cancel")
                } }
                .onAppear { if let saved { endpoint = saved.endpoint } }
                .onDisappear { token = ""; if !didInstall { cancelConnection() } }
                .onChange(of: scenePhase) { _, phase in
                    // The sheet can survive backgrounding. Revoke its unsaved
                    // credential and queued handshake as well as the live session.
                    if phase != .active { cancelConnection() }
                }
        }.interactiveDismissDisabled(broker.isBusy)
    }
    private func cancelConnection() {
        connectionAttempt = nil; connectionTask?.cancel(); connectionTask = nil
        token = ""; broker.disconnect()
    }
}

struct PluginToolCallView: View {
    @Bindable var broker: PluginBroker
    let tool: MCPToolDefinition
    @State private var arguments: String
    init(broker: PluginBroker, tool: MCPToolDefinition, initialArguments: String = "{}") {
        self.broker = broker
        self.tool = tool
        _arguments = State(initialValue: initialArguments)
    }
    @State private var error: String?
    @State private var executionTask: Task<Void, Never>?
    var body: some View {
        Form {
            Section("Untrusted tool description") {
                Text(tool.name).font(.headline)
                if let description = tool.description { Text(description).font(.footnote) }
                DisclosureGroup("Argument schema") { Text(pluginJSON(tool.inputSchema.json)).font(.caption.monospaced()) }
            }
            Section("Only these arguments will be sent") {
                TextEditor(text: $arguments).font(.body.monospaced()).frame(minHeight: 140)
                    .disabled(broker.isBusy).accessibilityIdentifier("plugin.arguments")
                Text("JSON object, at most 16 KiB. Chats, files, memory and location are not included automatically. Do not include passwords or unrelated private data.").font(.footnote).foregroundStyle(.secondary)
                Button("Review exact call") {
                    do { _ = try broker.prepareReview(toolName: tool.name, argumentText: arguments); error = nil }
                    catch { self.error = error.localizedDescription }
                }.disabled(!broker.canReviewTools).accessibilityIdentifier("plugin.review")
            }
            if let review = broker.review {
                Section("Approve this one call") {
                    Text(broker.activeConnection?.endpoint ?? "Disconnected").font(.caption)
                    Text(review.toolName).font(.headline)
                    Text(pluginJSON(review.arguments)).font(.caption.monospaced()).textSelection(.enabled)
                    Text("Run sends exactly this request to the server. It may change external data or cost money according to that provider. Canceling afterward cannot undo a remote action. Review only actions and data you intend to authorize.").font(.footnote)
                    Button("Run reviewed call") {
                        error = nil
                        executionTask = Task {
                            do { try await broker.execute(reviewID: review.id) }
                            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                            executionTask = nil
                        }
                    }.disabled(executionTask != nil || broker.isBusy).accessibilityIdentifier("plugin.run")
                }
            }
            if broker.isBusy {
                Section {
                    ProgressView("Waiting for the server…")
                    Button("Stop waiting and disconnect", role: .destructive) { broker.disconnect() }
                    Text("The server may already have acted. Check its state before retrying.").font(.footnote)
                }
            }
            if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            if let result = broker.lastResult {
                Section(result.isError ? "Server reported a tool error" : "Server result · not independent verification") {
                    ForEach(Array(result.content.enumerated()), id: \.offset) { _, content in
                        switch content {
                        case .text(let text): Text(text).textSelection(.enabled)
                        case .image(let data, let mimeType):
                            // Inert metadata only; no remote URL fetch or automatic image decoding.
                            Text("Image data returned: \(mimeType), \(data.count) bytes. Rendering is not supported here.").font(.footnote)
                        }
                    }
                    if let value = result.structuredContent { Text(pluginJSON(value)).font(.caption.monospaced()).textSelection(.enabled) }
                    Text("Treat remote results as untrusted information. They cannot authorize another call.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Review tool").navigationBarTitleDisplayMode(.inline)
            .onAppear { broker.clearResult(); broker.invalidateReview() }
            .onChange(of: arguments) { _, _ in broker.invalidateReview() }
            .onDisappear { executionTask?.cancel(); executionTask = nil; broker.invalidateReview(); if broker.isBusy { broker.disconnect() } }
    }
}

struct PluginExecutionLogView: View {
    @Bindable var journal: PluginJournal
    var body: some View {
        List {
            if journal.requiresRecovery { Text(PluginExecutionError.outcomeNotRecorded.localizedDescription).foregroundStyle(.red) }
            Section { Text("This log records dispatch and server reports, not independently verified effects. Interrupted calls become outcome unknown and are never automatically replayed. Arguments, credentials and result bodies are not saved.").font(.footnote) }
            if journal.records.isEmpty { Text("No tool calls yet") }
            ForEach(journal.records) { record in
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.toolName).font(.headline)
                    Text(record.state.title).font(.subheadline)
                    Text(record.createdAt, style: .date).font(.caption)
                    Text(record.id.uuidString).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Execution log")
    }
}

private func pluginJSON(_ value: MCPJSONValue) -> String {
    guard let data = try? value.encoded(maximumBytes: 1_048_576), let text = String(data: data, encoding: .utf8) else { return "JSON could not be displayed safely." }
    return text
}

/// Chooses from already-discovered tools. It never installs code or executes calls.
private struct PluginTaskProposalView: View {
    @Bindable var broker: PluginBroker
    @Bindable var model: AppModel
    @State private var goal = ""
    @State private var proposed: PluginToolProposal?
    @State private var catalogID: UUID?
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    @State private var attempt: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section("Describe the task") {
                TextField("What should this plugin do?", text: $goal, axis: .vertical)
                    .disabled(task != nil)
                Text("Drafting sends this goal and the connected tool schemas to your selected model. A remote model receives that text. Chats, memory, files, location and plugin tokens are not included. Nothing runs until you review the exact call.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Find a tool and draft arguments") { draftProposal() }
                    .disabled(task != nil || !broker.canReviewTools || model.isGenerating || model.selectedProvider?.provider == nil || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || goal.utf8.count > 4096)
                if task != nil {
                    ProgressView("Choosing from connected tools…")
                    Button("Cancel") { cancel() }
                }
            }
            if let proposed, catalogID == broker.proposalCatalogID, broker.canReviewTools,
               let tool = broker.tools.first(where: { $0.name == proposed.name }) {
                Section("Suggested call · not executed") {
                    Text(proposed.name)
                    Text(pluginJSON(proposed.arguments)).font(.caption.monospaced())
                    NavigationLink("Review exact call") {
                        PluginToolCallView(broker: broker, tool: tool, initialArguments: pluginJSON(proposed.arguments))
                    }
                }
            }
            if let failure { Section { Text(failure).foregroundStyle(.secondary) } }
        }.navigationTitle("Plugin task")
            .onChange(of: goal) { _, _ in proposed = nil; failure = nil }
            .onChange(of: model.selectedProviderID) { _, _ in cancel() }
            .onChange(of: broker.proposalCatalogID) { _, _ in cancel() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
            .onDisappear {
                if let attempt { model.revokeHeavyWork(id: attempt) }
                attempt = nil; task?.cancel(); task = nil
            }
    }

    private func cancel() {
        if let attempt { model.revokeHeavyWork(id: attempt) }
        attempt = nil; task?.cancel(); task = nil; proposed = nil; catalogID = nil
    }
    private func draftProposal() {
        guard broker.canReviewTools, !model.isGenerating, let provider = model.selectedProvider?.provider else { return }
        proposed = nil; failure = nil
        let id = UUID(), revision = broker.proposalCatalogID
        let selected = model.selectedProviderID, tools = broker.tools, submitted = goal
        attempt = id
        task = Task {
            do {
                try await model.beginHeavyWork(id: id, kind: .localAgent)
                try Task.checkCancellation()
                let result = try await PluginToolProposal.generate(goal: submitted, tools: tools, provider: provider)
                guard attempt == id, !Task.isCancelled, broker.canReviewTools,
                      broker.proposalCatalogID == revision, model.selectedProviderID == selected,
                      model.heavyWorkLease?.id == id, model.heavyWorkLease?.phase == .ready else { throw CancellationError() }
                proposed = result; catalogID = revision
                if result == nil { failure = "No supported call was identified in this connection. Choose another connected plugin or use its manual tool review. Nothing was executed." }
            } catch {
                if attempt == id && !Task.isCancelled { failure = "A valid tool proposal could not be prepared. Use manual tool review or revise the request. Nothing was executed." }
            }
            await model.finishLocalAgentWork(id: id)
            if attempt == id { task = nil; attempt = nil }
        }
    }
}
