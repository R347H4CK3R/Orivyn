import SwiftUI

struct LocalAgentView: View {
    @Bindable var model: AppModel
    @State private var session: LocalAgentSession?
    @State private var goal = ""
    @State private var planKind = "conversation_read"
    @State private var setupError: String?
    @State private var confirmArchive = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Form {
            Section("Recommended: reviewed conversation task") {
                Text("Jarvis can choose tools to read app information, installed model names, matching conversations, bounded pages of their saved messages, and saved memory notes, or calculate bounded arithmetic. All reasoning stays on your iPhone. This does not send messages, edit files, access websites or repair the app.").font(.caption)
                Text("Uses your selected installed local model. Saved task records stay in Orivyn; no external actions are available.").font(.caption)
                TextEditor(text: $goal).frame(minHeight: 80).accessibilityIdentifier("agent.goal")
                    .disabled(session?.isPreparingReadPlan == true || session?.proposedReadPlan != nil)
                Text("\(goal.utf8.count)/512 bytes").font(.caption2)
                Text("For a saved-conversation question, draft a read plan and review its search and message scope before approving it. Drafting uses only your request with the selected local model; saved messages are not supplied to it.").font(.caption)
                Picker("Plan scope", selection: $planKind) {
                    Text("Read messages").tag("conversation_read")
                    Text("Search only").tag("conversation_search")
                }.pickerStyle(.segmented).accessibilityIdentifier("agent.plan.kind")
                    .disabled(session?.isRunning == true || session?.proposedReadPlan != nil)
                Text("For Read messages, put the exact conversation title in quotation marks and include the message numbers. Example: Read message 2 of \"Project notes\".").font(.caption)
                Button("Draft plan for review") { session?.prepareReadPlan(goal: goal, kind: planKind) }
                    .disabled(session?.canManageSavedTasks != true || session?.proposedReadPlan != nil || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || goal.utf8.count > 512)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("agent.plan.draft")
                Text("Review the proposed scope, approve it, then tap Run. Required approved reads must finish before an answer is accepted; the answer's accuracy still needs your review.").font(.caption)
                DisclosureGroup {
                    Text("For app information, model lists, memory searches or arithmetic. This mode has no approved completion checklist: it can answer after a search without reading the message you asked about. For saved-message questions, use the reviewed plan above.").font(.caption).foregroundStyle(.orange)
                    Text("For arithmetic, use Calculate followed by the expression. Numbers, signs and parentheses must match; word-problem translations are not verified.").font(.caption)
                    Button("Create experimental task") { session?.create(goal: goal) }
                        .disabled(session?.canManageSavedTasks != true || session?.proposedReadPlan != nil || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || goal.utf8.count > 512)
                        .accessibilityIdentifier("agent.create")
                } label: {
                    Text("Other local tasks · experimental")
                        .accessibilityIdentifier("agent.experimental.options")
                }
            }
            if let setupError { Section { Text(setupError).foregroundStyle(.orange) } }
            if let session {
                if let warning = session.recoveryWarning { Section { Text(warning).font(.caption).foregroundStyle(.orange) } }
                if let error = session.error { Section { Text(error).foregroundStyle(.orange).accessibilityIdentifier("agent.error") } }
                if session.isPreparingReadPlan {
                    Section("Drafting local plan") {
                        HStack { ProgressView(); Text(session.status).font(.caption) }
                        Button("Stop drafting") { session.stop(cancelTask: false) }
                            .accessibilityIdentifier("agent.plan.stop")
                    }
                }
                if let proposal = session.proposedReadPlan {
                    Section("Review local plan") {
                        Text(proposal.goal).accessibilityIdentifier("agent.plan.goal")
                        readPlanSummary(proposal.plan)
                        Text("Check that this plan matches your question. Approval saves this scope; no search or message read starts until you tap Run. To change the scope, discard it and draft a new plan.").font(.caption)
                        Button("Approve and create task") { session.approveReadPlan() }
                            .disabled(!session.canManageSavedTasks).accessibilityIdentifier("agent.plan.approve")
                        Button("Discard plan", role: .destructive) { session.discardReadPlan() }
                            .disabled(!session.canManageSavedTasks).accessibilityIdentifier("agent.plan.discard")
                    }.accessibilityIdentifier("agent.plan.review")
                }
                if let task = session.snapshot {
                    Section("Current task") {
                        Text(task.goal)
                        if let plan = task.readPlan {
                            readPlanSummary(plan)
                            Text(task.status == "answered"
                                 ? "Approved steps recorded. The model answer still needs your review."
                                 : "The task can answer only after its approved steps are complete. Missing, ambiguous or changed evidence stops the task.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("This experimental task has no approved completion checklist. An answer does not prove that every requested read happened. Draft a new reviewed plan above for saved-message questions; this record is preserved.")
                                .font(.caption).foregroundStyle(.orange)
                                .accessibilityIdentifier("agent.unreviewedWarning")
                        }
                        LabeledContent("State", value: task.status)
                        LabeledContent("Read-only tool steps", value: "\(task.steps)/6")
                        Text(session.status).font(.caption).accessibilityIdentifier("agent.status")
                        HStack {
                            Button(task.status == "interrupted" ? "Resume" : "Run") { session.run() }
                                .disabled(session.isRunning || session.proposedReadPlan != nil || !["ready", "interrupted"].contains(task.status)).accessibilityIdentifier("agent.run")
                            Button("Pause") { session.stop(cancelTask: false) }.disabled(!session.isRunning || session.isPreparingReadPlan)
                            Button("Cancel task", role: .destructive) { session.stop(cancelTask: true) }
                                .disabled(session.isPreparingReadPlan || ["answered", "failed", "cancelled"].contains(task.status))
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

    @ViewBuilder
    private func readPlanSummary(_ plan: LocalReadPlan) -> some View {
        LabeledContent("Search", value: plan.query)
        Text("Search scans saved titles, messages, and extracted attachment text and may return matching excerpts.").font(.caption)
        if plan.kind == "conversation_search" {
            Text("Search results only. No additional message pages will be opened.").font(.caption)
        } else {
            LabeledContent("Conversation title", value: plan.title ?? "")
            LabeledContent("Message numbers", value: (plan.messageIndexes ?? []).map { String($0 + 1) }.joined(separator: ", "))
            Text("After searching, open only these message pages from one matching conversation. An ambiguous title or missing message stops the task.").font(.caption)
        }
    }
}
