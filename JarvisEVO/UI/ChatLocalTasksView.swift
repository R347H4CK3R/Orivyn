import SwiftUI

/// Local records are presented as evidence, never appended as hidden model context.
struct ChatLocalTasksView: View {
    @Bindable var model: AppModel
    let conversationID: UUID
    @State private var records: [LocalAgentSnapshot] = []
    @State private var failure: String?
    @State private var review: Review?
    private struct Review: Identifiable {
        let id = UUID()
        let goal: String
        let context: ChatLocalTaskContext
        let taskID: String?
    }
    private var context: ChatLocalTaskContext {
        ChatLocalTaskContext(conversationID: conversationID, conversationRevision: model.pluginResultConversationContext,
                             providerRevision: model.pluginProposalProviderContext)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Plan a saved-conversation task") {
                    review = Review(goal: model.draft, context: context, taskID: nil)
                }
                .disabled(model.selectedLocalAgentProvider == nil || !model.canBeginHeavyWork || model.draft.utf8.count > 512 || !model.pendingAttachments.isEmpty)
                .accessibilityIdentifier("chat.task.plan")
                Text("Uses only this draft with your local model to propose a saved-conversation search. You can select exact message reads in review. Limit: 512 UTF-8 bytes. Review and Run are required. Attachments are not included; your draft stays unchanged.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.orange) }
            if !records.isEmpty {
                DisclosureGroup {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(records) { record in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.goal).font(.subheadline).lineLimit(3)
                                    Text("Recorded stage: \(record.status) · \(record.history.count) recorded operations").font(.caption)
                                    if let answer = record.answer {
                                        Text("Model answer, not independently verified").font(.caption).foregroundStyle(.secondary)
                                        Text(answer).textSelection(.enabled)
                                    }
                                    ForEach(record.history) { event in
                                        DisclosureGroup {
                                            Text(event.result ?? "No result recorded.").font(.caption.monospaced()).textSelection(.enabled)
                                                .accessibilityIdentifier("chat.task.evidence.\(event.operationID)")
                                        } label: {
                                            Text("\(event.name): \(event.outcome)")
                                                .accessibilityIdentifier("chat.task.operation.\(event.operationID)")
                                        }
                                    }
                                    Button(["ready", "interrupted", "running"].contains(record.status) ? "Review / resume task" : "Inspect task") {
                                        review = Review(goal: record.goal, context: context, taskID: record.id)
                                    }.disabled(!model.canBeginHeavyWork)
                                        .accessibilityIdentifier("chat.task.inspect.\(record.id)")
                                }
                            }
                        }
                    }.frame(maxHeight: 210).accessibilityIdentifier("chat.task.records")
                    Text("Recorded local evidence only. An interrupted running stage is recovered when opened; resume is explicit. These cards are not sent to chat models.").font(.caption2)
                    Button("Refresh task status") { reload() }
                } label: {
                    // Container identifiers propagate over child controls on iOS 26.
                    // Identify only the header so records and action IDs remain distinct.
                    Text("Local tasks in this conversation (\(records.count))")
                        .accessibilityIdentifier("chat.task.list")
                }
            }
        }.padding(.horizontal).padding(.vertical, 4)
        .sheet(item: $review, onDismiss: reload) { item in
            NavigationStack {
                LocalAgentView(model: model, initialGoal: item.goal, chatContext: item.context,
                               initialTaskID: item.taskID, draftPlanOnOpen: item.taskID == nil)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { review = nil }.accessibilityIdentifier("chat.task.close") } }
            }
        }
        .task(id: conversationID) {
            repeat {
                reload()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            } while !Task.isCancelled
        }
    }
    private func reload() {
        guard model.selectedConversationID == conversationID, let directory = model.localAgentDirectory else { records = []; return }
        guard model.canBeginHeavyWork else { return } // Never scan disk while shared inference owns the runtime.
        do {
            let store = try LocalAgentStore(directory: directory)
            let batch = try store.records()
            var result: [LocalAgentSnapshot] = [], unreadable = batch.unreadable
            for raw in batch.values {
                do {
                    let record = try JSONDecoder().decode(LocalAgentSnapshot.self, from: Data(raw.utf8))
                    if try store.origin(id: record.id) == conversationID { result.append(record) }
                } catch { unreadable += 1 }
            }
            records = result
            failure = unreadable == 0 ? nil : "Some task records could not be read. Their files are retained."
        } catch { records = []; failure = "Task status could not be loaded. No task was started or deleted." }
    }
}
