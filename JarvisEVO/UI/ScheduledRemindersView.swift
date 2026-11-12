import SwiftUI

struct ScheduledRemindersView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var scheduler: ReminderScheduler
    @State private var showingForm = false
    @State private var error: String?

    init(scheduler: ReminderScheduler = .shared) {
        _scheduler = State(initialValue: scheduler)
    }

    var body: some View {
        List {
            Section {
                Label("Scheduled actions", systemImage: "clock.arrow.circlepath").font(.headline)
                Text("Create one-time local reminders delivered by iOS. These do not run AI, send messages, or operate other apps in the background.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if scheduler.authorization == .denied {
                    Text("Notifications are off for Orivyn. Existing pending reminders may not alert you.").foregroundStyle(.secondary)
                    Button("Open notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            } footer: {
                Text("Reminder titles and notes may appear on your lock screen. Focus, notification settings and device state can delay or suppress delivery.")
            }
            Section("Pending reminders · \(scheduler.reminders.count)/48") {
                if scheduler.reminders.isEmpty {
                    Text(scheduler.isBusy ? "Checking iOS reminders…" : "No pending reminders").foregroundStyle(.secondary)
                }
                ForEach(scheduler.reminders) { reminder in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reminder.title).font(.headline)
                        Text(reminder.date, format: .dateTime.month().day().year().hour().minute()).font(.subheadline)
                        if !reminder.notes.isEmpty { Text(reminder.notes).font(.subheadline).foregroundStyle(.secondary) }
                        Button("Cancel reminder", role: .destructive) {
                            Task {
                                do { try await scheduler.cancel(id: reminder.id) }
                                catch { self.error = error.localizedDescription }
                            }
                        }.buttonStyle(.borderless).disabled(scheduler.isBusy)
                    }.padding(.vertical, 4)
                }
            } footer: {
                Text("This list comes from iOS’s actual pending queue. Delivered, expired or canceled reminders are not recreated. Maximum 48 Orivyn reminders.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New reminder", systemImage: "plus") { showingForm = true }
                    .disabled(scheduler.isBusy).accessibilityIdentifier("reminder.new")
            }
        }
        .task { await scheduler.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await scheduler.refresh() } }
        }
        .refreshable { await scheduler.refresh() }
        .sheet(isPresented: $showingForm) { NewReminderForm(scheduler: scheduler) }
        .alert("Reminder could not be changed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}

private struct NewReminderForm: View {
    @Environment(\.dismiss) private var dismiss
    let scheduler: ReminderScheduler
    @State private var title = ""
    @State private var notes = ""
    @State private var date = Date().addingTimeInterval(60 * 60)
    @State private var error: String?

    private var validationError: String? {
        do { _ = try LocalReminder.validated(title: title, notes: notes, date: date, now: Date()); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Title", text: $title).accessibilityIdentifier("reminder.title")
                    Text("\(title.count)/120 characters · \(title.utf8.count)/480 UTF-8 bytes").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $notes).frame(minHeight: 100)
                        .accessibilityLabel("Optional notes").accessibilityIdentifier("reminder.notes")
                    Text("Optional notes · \(notes.utf8.count)/2,000 UTF-8 bytes").font(.caption).foregroundStyle(.secondary)
                }
                Section("When") {
                    DatePicker("Date and time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("reminder.date")
                    Text("Choose a future time within 365 days. Notifications use one-second precision and will not be scheduled earlier than the chosen time.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !title.isEmpty, let validationError { Text(validationError).font(.caption).foregroundStyle(.red) }
                }
                Section {
                    Text("Schedule asks iOS for notification permission if needed. The title and notes may be visible on your lock screen. Do not include secrets.")
                    Text("This is a local reminder, not a background AI task. iOS controls whether and when its alert appears.")
                }.font(.footnote).foregroundStyle(.secondary)
                if scheduler.isBusy { ProgressView("Confirming with iOS…") }
            }
            .disabled(scheduler.isBusy)
            .navigationTitle("New reminder").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(scheduler.isBusy).accessibilityIdentifier("reminder.form.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        Task {
                            do { _ = try await scheduler.create(title: title, notes: notes, date: date); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(validationError != nil || scheduler.isBusy).accessibilityIdentifier("reminder.schedule")
                }
            }
            .interactiveDismissDisabled(scheduler.isBusy)
            .alert("Could not schedule reminder", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
