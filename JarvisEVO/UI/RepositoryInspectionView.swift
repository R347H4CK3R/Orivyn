import SwiftUI

/// User-directed reads only. Private source is never given to a model or plugin.
struct RepositoryInspectionView: View {
    @State private var token = ""
    @State private var reference = ""
    @State private var client: RepositoryInspectionClient?
    @State private var snapshot: RepositoryInspectionSnapshot?
    @State private var file: RepositoryInspectionFile?
    @State private var work: Task<Void, Never>?
    @State private var operation: UUID?
    @State private var error: String?
    @State private var filter = ""
    @State private var visibleCount = 50
    private struct RepairSelection: Identifiable { let id = UUID(); let file: RepositoryInspectionFile }
    @State private var repairSelection: RepairSelection?
    @Environment(\.scenePhase) private var phase
    private var matching: [RepositoryInspectionEntry] {
        (snapshot?.files ?? []).filter { filter.isEmpty || $0.path.localizedCaseInsensitiveContains(filter) }
    }
    var body: some View {
        Form {
            Section("Private repository inspection") {
                Text("Reads R347H4CK3R/Orivyn directly from GitHub on this iPhone. No laptop, repository changes, code execution, builds or automatic fixes. Source content is untrusted data.").font(.caption)
                Text("Use a fine-grained GitHub token limited to this repository with Contents: Read-only. It is sent only to api.github.com, retained in memory for this screen, never saved, logged or sent to an AI provider.").font(.caption)
                if client == nil {
                    TextField("Branch, tag or commit (blank = default)", text: $reference).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Choose the source version to inspect. This does not prove it matches the installed app.").font(.caption)
                    SecureField("Read-only GitHub token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Connect and read repository") { connect() }.disabled(work != nil || token.isEmpty)
                } else {
                    Button("Disconnect and clear private source") { disconnect() }
                }
                if work != nil { ProgressView("Reading from GitHub…") }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            if let snapshot {
                Section("Pinned source snapshot") {
                    Text("Source ref: " + snapshot.branch)
                    Text("\(snapshot.files.count) inspectable files; \(snapshot.omittedFiles) oversized or unsupported entries omitted. File limit: 128 KiB.").font(.caption)
                    Text("Commit: " + snapshot.commitSHA).font(.caption.monospaced()).textSelection(.enabled)
                    Text("Files are verified against this commit's Git blob hashes. This is not a build or runtime test.").font(.caption)
                    TextField("Filter paths", text: $filter).onChange(of: filter) { _, _ in visibleCount = 50 }
                    ForEach(Array(matching.prefix(visibleCount)), id: \.path) { entry in
                        Button(entry.path) { read(entry.path, snapshotID: snapshot.id) }.disabled(work != nil)
                    }
                    if matching.count > visibleCount { Button("Show 50 more files") { visibleCount += 50 } }
                }
            }
            if let file {
                Section("Selected source") {
                    Text(file.path).font(.headline)
                    Button("Prepare a local change preview") { repairSelection = RepairSelection(file: file) }
                    Text("Verified Git blob: " + file.blobSHA).font(.caption.monospaced())
                    DisclosureGroup("Text review hints (not confirmed bugs)") {
                        let hints = RepositorySourceDiagnostics.inspect(path: file.path, text: file.text)
                        if hints.isEmpty { Text("No supported textual review markers found. This does not mean the file is bug-free.") }
                        ForEach(hints) { hint in
                            VStack(alignment: .leading) {
                                Text("Line \(hint.line): \(hint.kind)")
                                Text(hint.explanation).font(.caption)
                            }
                        }
                    }
                    Text(file.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }.navigationTitle("Inspect Orivyn source")
        .sheet(item: $repairSelection) { selection in
            NavigationStack { SourceRepairDraftView(file: selection.file) }
        }
        .onDisappear { disconnect() }
        .onChange(of: phase) { _, value in if value != .active { disconnect() } }
    }
    private func connect() {
        guard work == nil else { return }
        do {
            let requestedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard requestedReference.isEmpty || RepositoryInspectionReference.resolve(requestedReference, defaultBranch: "") != nil else {
                throw RepositoryInspectionError.reference
            }
            let next = try RepositoryInspectionClient(token: token)
            token = ""; client = next; error = nil
            let id = UUID(); operation = id
            work = Task { @MainActor in
                do {
                    let value = try await next.loadSnapshot(reference: requestedReference)
                    guard operation == id, !Task.isCancelled else { return }
                    snapshot = value
                } catch {
                    guard operation == id else { return }
                    self.error = error.localizedDescription
                    await next.clearCredentials(); client = nil
                }
                if operation == id { work = nil; operation = nil }
            }
        } catch { token = ""; self.error = error.localizedDescription }
    }
    private func read(_ path: String, snapshotID: UUID) {
        guard work == nil, let client else { return }
        let id = UUID(); operation = id; error = nil; file = nil
        work = Task { @MainActor in
            do {
                let value = try await client.readFile(path: path, snapshotID: snapshotID)
                guard operation == id, !Task.isCancelled else { return }
                file = value
            } catch { if operation == id { self.error = error.localizedDescription } }
            if operation == id { work = nil; operation = nil }
        }
    }
    private func disconnect() {
        repairSelection = nil
        operation = nil; work?.cancel(); work = nil
        let previous = client; client = nil; snapshot = nil; file = nil; token = ""; reference = ""; error = nil
        Task { await previous?.clearCredentials() }
    }
}

