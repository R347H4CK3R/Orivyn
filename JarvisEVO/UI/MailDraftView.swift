import SwiftUI
import MessageUI

struct MailDraftView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var recipient = ""
    @State private var subject = ""
    @State private var message = ""
    @State private var editor: MailDraft?
    @State private var status: String?
    @State private var mailAvailable = MFMailComposeViewController.canSendMail()
    @FocusState private var fieldFocused: Bool

    private var validationError: String? {
        do { _ = try MailDraft.validated(recipient: recipient, subject: subject, body: message); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        Form {
            Section {
                Text("Prepare a message, then review recipients and content in Apple's Mail editor. Only you can press Send. Orivyn cannot read your inbox or connect an email account.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !mailAvailable {
                    Text("Mail is not configured for sending on this device. Add a sending account in Apple's Mail settings, then return here. You can still edit this draft; nothing will be sent.")
                        .font(.footnote).accessibilityIdentifier("mail.unavailable")
                }
            }
            Section("Message draft") {
                TextField("Recipient (optional)", text: $recipient)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($fieldFocused).accessibilityIdentifier("mail.recipient")
                TextField("Subject", text: $subject).focused($fieldFocused).accessibilityIdentifier("mail.subject")
                TextEditor(text: $message).frame(minHeight: 160).focused($fieldFocused)
                    .accessibilityLabel("Message body").accessibilityIdentifier("mail.body")
                Text("Subject: \(subject.utf8.count)/512 bytes · Message: \(message.utf8.count)/32,768 bytes")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let validationError { Section { Text(validationError).font(.footnote).foregroundStyle(.red) } }
            if let status { Section { Text(status).font(.footnote).accessibilityIdentifier("mail.status") } }
            Section {
                Text("This form stays unchanged when the system editor closes. Changes made inside Mail are managed by Mail and are not copied back here. This draft is held in memory only while this screen stays open.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Email").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Review") { review() }.accessibilityLabel("Review in Mail")
                    .accessibilityIdentifier("mail.review")
                    .disabled(validationError != nil || editor != nil || scenePhase != .active)
            }
        }
        .sheet(item: $editor) { draft in
            MailEditor(draft: draft) { outcome in
                guard editor?.id == draft.id else { return }
                status = outcome
                editor = nil
            }.interactiveDismissDisabled()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { mailAvailable = MFMailComposeViewController.canSendMail() }
        }
    }

    private func review() {
        guard editor == nil, scenePhase == .active else { return }
        do {
            let draft = try MailDraft.validated(recipient: recipient, subject: subject, body: message)
            mailAvailable = MFMailComposeViewController.canSendMail()
            guard mailAvailable else {
                status = "Mail cannot send on this device yet. Your draft is unchanged. Configure a sending account in Apple's Mail settings to open its editor."
                return
            }
            fieldFocused = false
            status = nil
            editor = draft
        } catch { status = error.localizedDescription }
    }
}

private struct MailEditor: UIViewControllerRepresentable {
    let draft: MailDraft
    let completed: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        if !draft.recipient.isEmpty { controller.setToRecipients([draft.recipient]) }
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        return controller
    }
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    // UIKit delivers this UI completion on the main thread. The SDK's legacy
    // delegate protocol is nonisolated; retain runtime main-actor checking.
    @MainActor final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        private let completed: (String) -> Void
        private var didComplete = false
        init(completed: @escaping (String) -> Void) { self.completed = completed }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: (any Error)?) {
            guard !didComplete else { return }
            didComplete = true
            if let error {
                completed("Mail could not finish: \(error.localizedDescription). This form is unchanged; check Mail before retrying.")
                return
            }
            switch result {
            case .cancelled: completed("Mail was canceled. This form is unchanged.")
            case .saved: completed("Mail reports that the message was saved as a draft. This form is unchanged.")
            case .sent: completed("Mail accepted the message for sending. Delivery is not confirmed. This form is unchanged.")
            case .failed: completed("Mail could not send the message. This form is unchanged; check Mail before retrying.")
            @unknown default: completed("Mail closed with an unknown result. Check Mail before retrying; delivery is not confirmed.")
            }
        }
    }
}
