import SwiftUI
import EventKit
import EventKitUI

struct CalendarDraftView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var title = ""
    @State private var notes = ""
    @State private var start: Date
    @State private var end: Date
    @State private var editor: CalendarDraft?
    @State private var status: String?
    @FocusState private var fieldFocused: Bool

    init() {
        let start = Date().addingTimeInterval(3_600)
        _start = State(initialValue: start)
        _end = State(initialValue: start.addingTimeInterval(3_600))
    }

    private var validationError: String? {
        do { _ = try CalendarDraft.validated(title: title, notes: notes, start: start, end: end); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        Form {
            Section {
                Text("Prepare an event and review it in Apple's Calendar editor. Choose the calendar and tap Add there to save. Orivyn does not read existing events, request broad calendar access, or save silently.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Event draft") {
                TextField("Title", text: $title).focused($fieldFocused).accessibilityIdentifier("calendar.title")
                Text("\(title.count)/120 characters · \(title.utf8.count)/480 bytes").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $notes).frame(minHeight: 100).focused($fieldFocused)
                    .accessibilityLabel("Event notes").accessibilityIdentifier("calendar.notes")
                Text("Notes: \(notes.utf8.count)/4,096 bytes").font(.caption).foregroundStyle(.secondary)
            }
            Section("When") {
                DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Ends", selection: $end, displayedComponents: [.date, .hourAndMinute])
                if !title.isEmpty, let validationError { Text(validationError).font(.footnote).foregroundStyle(.red) }
            }
            if let status { Section { Text(status).font(.footnote).accessibilityIdentifier("calendar.status") } }
            Section {
                Text("Canceling the system editor keeps this form unchanged. Edits made inside Calendar are not copied back here. Calendar availability and synchronization depend on this device's accounts. This form stays in memory only while this screen stays open.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Review") { review() }.accessibilityLabel("Review in Calendar")
                    .accessibilityIdentifier("calendar.review")
                    .disabled(validationError != nil || editor != nil || scenePhase != .active)
            }
        }
        .sheet(item: $editor) { draft in
            CalendarEditor(draft: draft) { outcome in
                guard editor?.id == draft.id else { return }
                status = outcome
                editor = nil
            }.interactiveDismissDisabled()
        }
    }

    private func review() {
        guard editor == nil, scenePhase == .active else { return }
        do {
            let draft = try CalendarDraft.validated(title: title, notes: notes, start: start, end: end)
            fieldFocused = false
            status = nil
            editor = draft
        } catch { status = error.localizedDescription }
    }
}

private struct CalendarEditor: UIViewControllerRepresentable {
    let draft: CalendarDraft
    let completed: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        // iOS 17+ provides this system review UI without broad calendar permission.
        // Never query a calendar list/default or call EKEventStore.save from Orivyn.
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.notes = draft.notes
        event.startDate = draft.start
        event.endDate = draft.end
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    // UIKit delivers this UI completion on the main thread. The SDK's legacy
    // delegate protocol is nonisolated; retain runtime main-actor checking.
    @MainActor final class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
        private let completed: (String) -> Void
        private var didComplete = false
        init(completed: @escaping (String) -> Void) { self.completed = completed }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            guard !didComplete else { return }
            didComplete = true
            switch action {
            case .canceled: completed("Calendar was canceled. This form is unchanged.")
            case .saved: completed("Calendar reports that the event was saved. Account synchronization is not confirmed. This form is unchanged.")
            case .deleted: completed("Calendar reports that the event was deleted. This form is unchanged.")
            @unknown default: completed("Calendar closed with an unknown result. Check Calendar before trying again.")
            }
        }
    }
}
