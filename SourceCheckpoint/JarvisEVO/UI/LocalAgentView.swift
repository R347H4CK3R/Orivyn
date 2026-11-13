import SwiftUI

struct LocalAgentView: View {
    @Bindable var model: AppModel
    @State private var session: LocalAgentSession?
    @State private var goal = ""
    @State private var setupError: String?
    @State private var confirmArchive = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Form {
            Section("Local read-only tasks") {
                Text("Jarvis can choose tools to read app information, installed model names and matching conversation excerpts, or calculate bounded arithmetic. All reasoning stays on your iPhone. This does not send messages, edit files, access websites or repair the app.").font(.caption)
                Text("Experimental: small local models can skip needed tools or misread results. Inspect the recorded evidence; an answer is not verified just because the task finished.").font(.caption).foregroundStyle(.orange)
                Text("For arithmetic, use Calculate followed by the expression. Numbers, signs and parentheses must match; word-problem translations are not verified.").font(.caption)
                Text("Uses your selected installed local model. Saved task records stay in Orivyn; no external actions are available.").font(.caption)
                TextEditor(text: $goal).frame(minHeight: 80).accessibilityIdentifier("agent.goal")
                Text("\(goal.utf8.count)/512 bytes").font(.caption2)
                Button("Create task") { session?.create(goal: goal) }
                    .disabled(session == nil || session?.isRunning == true || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || goal.utf8.count > 512)
                    .accessibilityIdentifier("agent.create")
            }
            if let setupError { Section { Text(setupError).foregroundStyle(.orange) } }
            if let session {
                if let warning = session.recoveryWarning { Section { Text(warning).font(.caption).foregroundStyle(.orange) } }
                if let error = session.error { Section { Text(error).foregroundStyle(.orange).accessibilityIdentifier("agent.error") } }
                if let task = session.snapshot {
                    Section("Current task") {
                        Text(task.goal)
                        LabeledContent("State", value: task.status)
                        LabeledContent("Read-only tool steps", value: "\(task.steps)/6")
                        Text(session.status).font(.caption).accessibilityIdentifier("agent.status")
                        HStack {
                            Button(task.status == "interrupted" ? "Resume" : "Run") { session.run() }
                                .disabled(session.isRunning || !["ready", "interrupted"].contains(task.status)).accessibilityIdentifier("agent.run")
                            Button("Pause") { session.stop(cancelTask: false) }.disabled(!session.isRunning)
                            Button("Cancel task", role: .destructive) { session.stop(cancelTask: true) }
                                .disabled(["answered", "failed", "cancelled"].contains(task.status))
                        }
                        Button("Archive task") { confirmArchive = true }
                            .disabled(!session.canManageSavedTasks).accessibilityIdentifier("agent.archive")
                        ForEach(task.history) { event in
                            if let evidence = event.calculationEvidence(goal: task.goal) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Recomputed arithmetic").font(.caption).foregroundStyle(.secondary)
                                    Text(evidence.expression + " = " + evidence.result).textSelection(.enabled)
                                        .accessibilityIdentifier("agent.calculationEvidence")
                                    Text("Approximate arithmetic, checked against your expression. This does not verify the model answer below.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let answer = task.answer {
                            Text("Model answer · not verified; no external action performed").font(.caption).foregroundStyle(.secondary)
                            Text(answer).textSelection(.enabled).accessibilityIdentifier("agent.answer")
                        }
                        if let failure = task.error { Text(failure).font(.caption).foregroundStyle(.orange) }
                        ForEach(task.history) { event in
                            DisclosureGroup("\(event.name): \(event.outcome)") {
                                Text(event.result ?? "No result recorded.").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                    }
                }
                Section("Archived tasks") {
                    Text("Archived records remain on this iPhone. Restore a task to use it again; archiving frees an active-task slot.").font(.caption)
                    HStack {
                        Button("Previous page") { session.changeArchivePage(-1) }.disabled(!session.canManageSavedTasks || session.archivePage == 0)
                        Text("Page \(session.archivePage + 1)")
                        Button("Next page") { session.changeArchivePage(1) }.disabled(!session.canManageSavedTasks || (session.archivePage + 1) * 50 >= session.archivedTotal)
                    }
                    ForEach(session.archivedRecords) { task in
                        Button("Restore: " + task.goal) { session.restoreArchived(id: task.id) }.disabled(!session.canManageSavedTasks)
                    }
                }
                Section("Saved tasks") {
                    ForEach(session.records) { task in
                        Button { session.select(id: task.id) } label: {
                            VStack(alignment: .leading) { Text(task.goal).lineLimit(2); Text(task.status).font(.caption).foregroundStyle(.secondary) }
                        }.disabled(!session.canManageSavedTasks)
                    }
                }
            }
        }.navigationTitle("Local tasks")
        .confirmationDialog("Archive this task? Its data will be retained and can be restored.", isPresented: $confirmArchive) {
            Button("Archive task") { session?.archiveSelected() }
        }
        .task {
            guard session == nil else { return }
            do {
                guard let directory = model.localAgentDirectory else { throw LocalAgentError.unavailable }
                session = try LocalAgentSession(model: model, directory: directory)
            } catch { setupError = error.localizedDescription }
        }
        .onDisappear { session?.stop(cancelTask: false) }
        .onChange(of: phase) { _, phase in if phase != .active { session?.stop(cancelTask: false) } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in session?.stop(cancelTask: false) }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { session?.stop(cancelTask: false) }
        }
    }
}
