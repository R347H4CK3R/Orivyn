import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The app coordinator supplies these closures. A successful preparation is not
/// a database commit; only the commit closure can return a committed outcome.
@MainActor
struct ArchiveRestoreView: View {
    struct Review: Identifiable, Sendable, Equatable {
        let jobID: UUID
        let conversationCount: Int
        let messageCount: Int
        let unresolvedCount: Int
        let omittedCount: Int
        let retainedFileCount: Int
        let archiveSHA256: String
        var id: UUID { jobID }
    }
    enum CommitOutcome: Sendable {
        case committed(String)
        /// History is current; only the retained preparation marker needs repair.
        case committedMaintenancePending(String)
        /// Database commit succeeded, but refreshing the visible catalog failed.
        /// Never describe this as an uncommitted restore or offer duplicate retry.
        case committedReloadPending(String)
    }
    typealias Progress = @Sendable (String) -> Void
    let prepare: @MainActor (URL, @escaping Progress) async throws -> Review
    let commit: @MainActor (Review, @escaping Progress) async throws -> CommitOutcome
    let reloadReviews: @MainActor (@escaping Progress) async throws -> [Review]

    var loadInventory: (@MainActor (Review, Int) async throws -> ArchiveRestoreInventory.Page)?
    var reloadInventoryReviews: (@MainActor () async throws -> [Review])?

    private struct LogLine: Identifiable {
        let id = UUID()
        let time = Date()
        let text: String
    }
    @Environment(\.scenePhase) private var scenePhase
    @State private var lifetime = ArchiveRestoreLifetime()
    @State private var active = false
    @State private var lifecycle = UUID()
    @State private var pickerLifecycle: UUID?
    @State private var choosing = false
    @State private var operation: Task<Void, Never>?
    @State private var operationID: UUID?
    @State private var progressMailbox: ArchiveRestoreProgress?
    @State private var progressConsumer: Task<Void, Never>?
    @State private var cancelling = false
    @State private var review: Review?
    @State private var retainedReviews: [Review] = []
    @State private var inventoryReviews: [Review] = []
    @State private var inventoryReview: Review?
    @State private var inventoryPage: ArchiveRestoreInventory.Page?
    @State private var lines: [LogLine] = []
    @State private var errorText: String?
    @State private var status = "Choose your complete ChatGPT ZIP. Nothing is uploaded."
    @State private var committing = false
    @State private var lastProgressAt = Date()

    var body: some View {
        let renderedLifecycle = lifecycle
        let renderedLifetime = lifetime
        return List {
            Section("Restore a complete archive") {
                Text("Preparation keeps the original ZIP and unsupported files. Supported conversations are prepared as history, not just memory excerpts. Nothing is added to history until you review and confirm.")
                    .font(.footnote)
                Button("Choose ZIP…") {
                    pickerLifecycle = lifecycle; choosing = true
                    append("Presenting ZIP picker…")
                }
                    .disabled(operation != nil)
                    .accessibilityIdentifier("archive.choose-zip")
                Text(status).font(.caption).accessibilityIdentifier("archive.status")
                if operation != nil {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("Task pending · last reported progress \(max(0, Int(context.date.timeIntervalSince(lastProgressAt)))) seconds ago. Refreshed every 30 seconds; this is not a completed-work estimate.")
                            .font(.caption).accessibilityIdentifier("archive.heartbeat")
                    }
                    ProgressView(cancelling ? "Waiting for cancellation…" : "Working on actual files…")
                    if !committing {
                        Button(cancelling ? "Cancelling…" : "Cancel preparation", role: .cancel) { requestCancellation() }
                            .disabled(cancelling)
                            .accessibilityIdentifier("archive.cancel")
                    }
                }
                if let errorText { Text(errorText).foregroundStyle(.orange).accessibilityIdentifier("archive.error") }
            }
            if let review {
                Section("Review prepared restore") {
                    Text("\(review.conversationCount) conversations · \(review.messageCount) messages")
                    Text("\(review.retainedFileCount) files retained · \(review.unresolvedCount) retained unlinked reference records · \(review.omittedCount) mapping nodes not activated")
                        .font(.caption)
                    Text("Internal, hidden and private records are not activated as chat instructions. Unsupported and unresolved data stays in the retained archive. Unresolved media is not claimed as a working attachment.").font(.footnote)
                    Text("Reference counts cover supported visible messages only, not every missing media item. Other content types and alternative branches may exist only in the original ZIP.").font(.footnote)
                    if loadInventory != nil {
                        Button("Inspect per-message retained references") { inspectInventory(review, offset: 0) }
                            .disabled(operation != nil).accessibilityIdentifier("archive.inspect-media")
                    }
                    Text("Your local edits are preserved. Imported history cannot authorize tools. If you later choose an online model, selected history may be sent to that provider.").font(.footnote)
                    Text("ZIP SHA-256: \(review.archiveSHA256)").font(.caption2).textSelection(.enabled)
                    Button("Restore reviewed conversations") { beginCommit(review) }
                        .disabled(operation != nil)
                        .accessibilityIdentifier("archive.confirm")
                    Button("Leave prepared for later", role: .cancel) {
                        self.review = nil
                        status = "Prepared files retained. Review them again before restoring."
                    }.disabled(operation != nil)
                }
            }
            Section("Retained preparations") {
                Button("Refresh retained preparations") { refresh() }
                    .disabled(operation != nil)
                    .accessibilityIdentifier("archive.refresh-retained")
                if retainedReviews.isEmpty { Text("No retained preparations loaded.").font(.caption) }
                ForEach(retainedReviews) { item in
                    Button("Review \(item.conversationCount) conversations · \(item.jobID.uuidString.prefix(8))") {
                        review = item; errorText = nil
                        status = "Retained preparation selected. Files will be verified again before commit."
                    }.disabled(operation != nil)
                }
            }
            inventorySections
            Section("Live processing log (latest 200)") {
                Text("Display progress is coalesced during busy work. No invented percentages. A quiet log can mean a long-running operation, not necessarily a stall.").font(.caption)
                ForEach(lines) { line in
                    HStack(alignment: .top) {
                        Text(line.time, style: .time).monospacedDigit().foregroundStyle(.secondary)
                        Text(line.text).textSelection(.enabled)
                    }.font(.caption)
                }
            }
        }
        .navigationTitle("Restore ChatGPT ZIP")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(operation != nil || choosing)
        .interactiveDismissDisabled(operation != nil || choosing)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
            guard active, renderedLifetime.isValid, renderedLifetime === lifetime,
                  renderedLifecycle == lifecycle, pickerLifecycle == renderedLifecycle else { return }
            pickerLifecycle = nil
            append("ZIP picker returned a result.")
            switch result {
            case .success(let urls): if let url = urls.first { beginPreparation(url) }
            case .failure(let error): errorText = error.localizedDescription
            }
        }
        .background(ArchiveRestoreLifetimeObserver(lifetime: renderedLifetime).frame(width: 0, height: 0))
        .onAppear { activateLifetime() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { invalidateLifetime(reason: "App backgrounded") }
            else if phase == .active { activateLifetime() }
        }
        .onDisappear {
            // A covering document picker may hide its host. Do not tear down the
            // presentation we just requested. True hierarchy removal is separately
            // revoked synchronously by the observer's dismantleUIView callback.
            if choosing {
                append("Restore view covered while ZIP picker is presented.")
            } else { invalidateLifetime(reason: "Restore view left") }
        }
    }

    @ViewBuilder private var inventorySections: some View {
        if reloadInventoryReviews != nil {
            Section("Retained media inventory") {
                Text("Read-only metadata from preserved preparations, including completed imports. No media files are linked, opened, downloaded or executed.").font(.footnote)
                Button("Refresh retained media inventories") { refreshInventoryReviews() }
                    .disabled(operation != nil).accessibilityIdentifier("archive.refresh-media")
                ForEach(inventoryReviews) { item in
                    Button("Inspect retained media · " + String(item.jobID.uuidString.prefix(8))) { inspectInventory(item, offset: 0) }
                        .disabled(operation != nil)
                }
            }
        }
        if let page = inventoryPage, let selected = inventoryReview {
            Section("Per-message retained references") {
                Text("\(page.totalRecords) retained reference records across \(page.totalMessages) messages. This is not a complete media count.")
                    .accessibilityIdentifier("archive.media-summary")
                Text("Showing \(page.entries.count) messages from offset \(page.offset). These records do not establish a matching file or working attachment. Existing local conversations may differ from this archive.").font(.caption)
                ForEach(page.entries) { item in
                    VStack(alignment: .leading) {
                        Text(verbatim: item.title)
                        Text("Message \(item.messageIndex) · " + item.id.uuidString).font(.caption2).textSelection(.enabled)
                        Text("\(item.totalRecords) unlinked records: \(item.contentPartCount) content parts, \(item.attachmentMetadataCount) attachment metadata, \(item.otherCount) other.").font(.caption)
                    }
                }
                if page.offset > 0 {
                    Button("Previous messages") { inspectInventory(selected, offset: max(0, page.offset - 50)) }.disabled(operation != nil)
                }
                if let next = page.nextOffset {
                    Button("Next messages") { inspectInventory(selected, offset: next) }.disabled(operation != nil)
                }
                Button("Close inventory") { inventoryPage = nil; inventoryReview = nil }.disabled(operation != nil)
            }
        }
    }

    @MainActor private func activateLifetime() {
        if !lifetime.isValid { lifetime = ArchiveRestoreLifetime(); lifecycle = UUID() }
        active = true
    }
    @MainActor private func invalidateLifetime(reason: String) {
        lifetime.invalidate()
        active = false; lifecycle = UUID(); pickerLifecycle = nil; choosing = false
        append(reason + "; pending picker callbacks invalidated.")
        // A commit may already be durable and is not cancelled here.
        if !committing { requestCancellation() }
    }

    @MainActor private func append(_ text: String) {
        let bounded = String(text.prefix(1000))
        lines.append(LogLine(text: bounded))
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        status = bounded; lastProgressAt = Date()
    }
    @MainActor private func progress(for id: UUID) -> Progress {
        progressMailbox?.finish()
        progressConsumer?.cancel()
        let mailbox = ArchiveRestoreProgress()
        progressMailbox = mailbox
        progressConsumer = Task { @MainActor in
            for await line in mailbox.stream {
                guard !Task.isCancelled, operationID == id else { return }
                append(line)
                // Bound redraw frequency too; the producer never waits for UI.
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
        }
        return { line in mailbox.report(line) }
    }
    @MainActor private func beginPreparation(_ url: URL) {
        guard active, operation == nil else { return }
        let id = UUID(); operationID = id
        review = nil; errorText = nil; cancelling = false
        append("Opening selected ZIP…")
        operation = Task { @MainActor in
            defer { finish(id) }
            do {
                let prepared = try await prepare(url, progress(for: id))
                try Task.checkCancellation()
                review = prepared
                if !retainedReviews.contains(where: { $0.jobID == prepared.jobID }) { retainedReviews.append(prepared) }
                append("Preparation verified. Review before adding conversations to history.")
            } catch is CancellationError {
                append("Preparation stopped. Existing history was not changed; retained files remain available.")
            } catch {
                errorText = error.localizedDescription
                append("Preparation stopped with an error. No restore commit was requested.")
            }
        }
    }
    @MainActor private func beginCommit(_ selected: Review) {
        guard operation == nil else { return }
        let id = UUID(); operationID = id; committing = true; errorText = nil
        append("Revalidating prepared files before the history transaction…")
        operation = Task { @MainActor in
            defer { finish(id) }
            do {
                let outcome = try await commit(selected, progress(for: id))
                review = nil
                retainedReviews.removeAll { $0.jobID == selected.jobID }
                switch outcome {
                case .committed(let message): append(message)
                case .committedMaintenancePending(let message):
                    append(message)
                    errorText = "History is restored and available. Preparation-marker maintenance is pending; refresh retained preparations to retry."
                case .committedReloadPending(let message):
                    append("History was committed. \(message)")
                    errorText = "The visible history still needs a refresh. Do not import again to fix this."
                }
            } catch {
                // Coordinator must return a committed outcome after any durable
                // commit; throwing is reserved for an uncommitted transaction.
                errorText = error.localizedDescription
                append("Restore did not commit. Preparation retained for review and retry.")
            }
        }
    }
    @MainActor private func refresh() {
        guard operation == nil else { return }
        let id = UUID(); operationID = id; errorText = nil
        append("Checking retained preparations…")
        operation = Task { @MainActor in
            defer { finish(id) }
            do {
                retainedReviews = try await reloadReviews(progress(for: id))
                try Task.checkCancellation()
                append("Loaded \(retainedReviews.count) retained preparations. Revalidation is required before commit.")
            } catch is CancellationError { append("Retained-preparation check cancelled.") }
            catch { errorText = error.localizedDescription; append("Could not load retained preparations.") }
        }
    }
    @MainActor private func inspectInventory(_ selected: Review, offset: Int) {
        guard operation == nil, let loadInventory else { return }
        let id = UUID(); operationID = id; errorText = nil
        inventoryPage = nil; inventoryReview = nil
        append("Reading bounded retained-reference inventory…")
        operation = Task { @MainActor in
            defer { finish(id) }
            do {
                let page = try await loadInventory(selected, offset)
                try Task.checkCancellation()
                guard active, lifetime.isValid, operationID == id else { return }
                inventoryReview = selected; inventoryPage = page
                append("Read-only inventory loaded. No media was linked or activated.")
            } catch is CancellationError { append("Inventory read cancelled.") }
            catch { errorText = error.localizedDescription; append("Could not verify retained inventory.") }
        }
    }
    @MainActor private func refreshInventoryReviews() {
        guard operation == nil, let reloadInventoryReviews else { return }
        let id = UUID(); operationID = id; errorText = nil
        append("Checking retained media inventories…")
        operation = Task { @MainActor in
            defer { finish(id) }
            do {
                let items = try await reloadInventoryReviews()
                try Task.checkCancellation()
                guard active, lifetime.isValid, operationID == id else { return }
                inventoryReviews = items
                append("Loaded \(items.count) retained inventories; opening one never restores history.")
            } catch is CancellationError { append("Inventory listing cancelled.") }
            catch { errorText = error.localizedDescription; append("Could not list retained inventories.") }
        }
    }
    @MainActor private func requestCancellation() {
        guard let operation, !committing, !cancelling else { return }
        cancelling = true
        append("Cancellation requested; waiting for the file operation to stop safely…")
        operation.cancel()
        // Keep operation and operationID until the task actually returns. No new
        // preparation can race the still-running worker or its Files permissions.
    }
    @MainActor private func finish(_ id: UUID) {
        guard operationID == id else { return }
        progressMailbox?.finish(); progressMailbox = nil
        progressConsumer?.cancel(); progressConsumer = nil
        operation = nil; operationID = nil; cancelling = false; committing = false
    }
}

/// Unlike onDisappear, dismantling represents removal of this view hierarchy,
/// not merely another controller covering it. The non-observable reference token
/// is revoked synchronously, without mutating SwiftUI state during dismantling.
private struct ArchiveRestoreLifetimeObserver: UIViewRepresentable {
    let lifetime: ArchiveRestoreLifetime
    final class Witness: UIView { var lifetime: ArchiveRestoreLifetime? }
    func makeUIView(context: Context) -> Witness {
        let view = Witness(); view.isUserInteractionEnabled = false; view.lifetime = lifetime
        return view
    }
    func updateUIView(_ view: Witness, context: Context) { view.lifetime = lifetime }
    static func dismantleUIView(_ view: Witness, coordinator: ()) { view.lifetime?.invalidate() }
}
