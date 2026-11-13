import SwiftUI

struct VerifiedLocalReadView: View {
    @Bindable var model: AppModel
    @State private var session: VerifiedLocalReadSession?
    @State private var appInfo = true
    @State private var installedModels = true
    @State private var searchEnabled = false
    @State private var query = ""
    @State private var memoryEnabled = false
    @State private var memoryQuery = ""
    @State private var requestText = ""
    @State private var routingMessage: String?
    @State private var setupError: String?
    @State private var confirmArchive = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Form {
            Section("Describe a supported read") {
                Text("English request matching for these four tools only, not general AI autonomy. Example: What app is this and what models are installed? Search example: Search conversations for \"USB restore\".").font(.caption)
                Text("Memory example: Search saved memories for \"cafe\".").font(.caption)
                TextField("Describe the local reads", text: $requestText, axis: .vertical)
                Button("Suggest a read plan") {
                    do {
                        guard let proposal = try session?.propose(requestText) else { return }
                        routingMessage = proposal.message
                        if proposal.status == "matched", let request = proposal.request {
                            appInfo = request.appInfo; installedModels = request.installedModels
                            searchEnabled = request.searchQuery != nil; query = request.searchQuery ?? ""
                            memoryEnabled = request.memoryQuery != nil; memoryQuery = request.memoryQuery ?? ""
                        } else {
                            appInfo = false; installedModels = false; searchEnabled = false; query = ""
                            memoryEnabled = false; memoryQuery = ""
                        }
                    } catch { routingMessage = error.localizedDescription }
                }.disabled(session?.canManage != true || requestText.utf8.count > 1024)
                if let routingMessage { Text(routingMessage).font(.caption).foregroundStyle(.secondary) }
                Text("Review the selected operations below. Suggesting a plan does not create or run it.").font(.caption)
            }
            Section("Verified local reads") {
                Text("Choose exact read-only operations. A deterministic plan reads your app state and shows the returned facts without an AI model writing or interpreting an answer. This is not general autonomous reasoning or proof that conversation content is true.").font(.caption)
                Toggle("App identity and capability metadata", isOn: $appInfo)
                Toggle("Installed model names", isOn: $installedModels)
                Toggle("Search local conversations", isOn: $searchEnabled)
                if searchEnabled {
                    TextField("Exact search query", text: $query)
                    Text("Searches at most 500 conversations and returns up to 10 matches. Names and excerpts can be shortened; result limits are shown.").font(.caption)
                }
                Toggle("Search saved memory", isOn: $memoryEnabled)
                if memoryEnabled {
                    TextField("Literal saved-memory query", text: $memoryQuery)
                    Text("Reads at most 500 saved notes and returns up to 10 matching excerpts. Matching ignores case and accents. Excerpts may be shortened and are evidence of what you saved, not independently verified facts. Selected excerpts are saved in this on-device plan report. Nothing is sent to a model or server.").font(.caption)
                }
                Button("Create read plan") { session?.create(appInfo: appInfo, installedModels: installedModels, searchQuery: searchEnabled ? query : nil, memoryQuery: memoryEnabled ? memoryQuery : nil) }
                    .disabled(session?.canManage != true || !(appInfo || installedModels || searchEnabled || memoryEnabled) || searchEnabled && (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || query.utf8.count > 256) || memoryEnabled && (memoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || memoryQuery.utf8.count > 256))
                    .accessibilityIdentifier("verified.create")
            }
            if let setupError { Text(setupError).foregroundStyle(.orange) }
            if let session {
                if let error = session.error { Text(error).foregroundStyle(.orange) }
                if let snapshot = session.snapshot {
                    Section("Read plan") {
                        Text("State: " + snapshot.status).accessibilityIdentifier("verified.state")
                        LabeledContent("Completed reads", value: String(snapshot.completed))
                        Button(snapshot.status == "interrupted" ? "Resume reads" : "Run selected reads") { session.run() }
                            .disabled(!session.canManage || !["ready", "interrupted"].contains(snapshot.status)).accessibilityIdentifier("verified.run")
                        Button("Stop after current read") { session.stop() }.disabled(!session.isRunning)
                        Button("Archive report") { confirmArchive = true }.disabled(!session.canManage)
                        Text("Source evidence, not a model answer").font(.headline)
                        Text(pretty(session.report)).font(.system(.caption, design: .monospaced)).textSelection(.enabled).accessibilityIdentifier("verified.report")
                    }
                }
                Section("Saved plans") {
                    ForEach(session.records) { record in
                        Button("\(record.id.prefix(8)) · \(record.status) · \(record.completed) reads") { session.select(id: record.id) }.disabled(!session.canManage)
                    }
                }
                Section("Archived plans") {
                    HStack {
                        Button("Previous") { session.changeArchivePage(-1) }.disabled(!session.canManage || session.archivePage == 0)
                        Text("Page \(session.archivePage + 1)")
                        Button("Next") { session.changeArchivePage(1) }.disabled(!session.canManage || (session.archivePage + 1) * 50 >= session.archivedTotal)
                    }
                    ForEach(session.archivedRecords) { record in
                        Button("Restore \(record.id.prefix(8)) · \(record.status)") { session.restore(id: record.id) }.disabled(!session.canManage)
                    }
                }
            }
        }.navigationTitle("Verified local reads")
        .confirmationDialog("Archive this plan? Its data remains available to restore.", isPresented: $confirmArchive) {
            Button("Archive plan") { session?.archive() }
        }
        .task {
            guard session == nil else { return }
            do {
                guard let directory = model.verifiedReadDirectory else { throw LocalAgentError.unavailable }
                session = try VerifiedLocalReadSession(model: model, directory: directory)
            } catch { setupError = error.localizedDescription }
        }
        .onDisappear { session?.stop() }
        .onChange(of: phase) { _, phase in if phase != .active { session?.stop() } }
    }
    private func pretty(_ text: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let bytes = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let rendered = String(data: bytes, encoding: .utf8) else { return text }
        return rendered
    }
}
