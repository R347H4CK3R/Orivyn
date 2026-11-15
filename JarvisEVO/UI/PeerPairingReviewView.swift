#if ORIVYN_PEER_TLS_SPIKE && os(iOS)
import SwiftUI

/// Explicit review surface only. The owner must validate the offer, bind its
/// lifetime to this presentation, and durably retain/revoke approved authority.
struct PeerPairingReviewView: View {
    struct ConversationChoice: Identifiable {
        let id: UUID
        let title: String
    }
    let offer: PeerPairingOffer
    let localFingerprint: String
    let conversations: [ConversationChoice]
    let approve: @MainActor (String, Set<UUID>) async throws -> Void
    let cancel: @MainActor () -> Void
    @State private var fingerprint = ""
    @State private var selected = Set<UUID>()
    @State private var isApproving = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Verify both devices") {
                Text("On the other device, compare this device’s full fingerprint:")
                Text(localFingerprint).font(.caption.monospaced()).textSelection(.enabled)
                Text("Type or paste the full 64-character fingerprint shown on the other device itself. Do not copy it from the imported pairing document.")
                TextField("Other device’s fingerprint", text: $fingerprint)
                    .font(.caption.monospaced())
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("peerPairingFingerprint")
            }
            Section {
                ForEach(conversations) { conversation in
                    Button {
                        if selected.contains(conversation.id) { selected.remove(conversation.id) }
                        else { selected.insert(conversation.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(conversation.title)
                                Text(conversation.id.uuidString).font(.caption2.monospaced())
                            }
                            Spacer()
                            Image(systemName: selected.contains(conversation.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    .accessibilityValue(selected.contains(conversation.id) ? "Selected" : "Not selected")
                }
            } header: { Text("Approve conversations") }
              footer: {
                Text("Imported titles and IDs are untrusted proposals. Compare them on the other device. Only selected conversation IDs are authorized. Attachments, credentials and other conversations are excluded. Pairing does not enable background transfers.")
              }
            if let failure { Text(failure).foregroundStyle(.red).accessibilityIdentifier("peerPairingFailure") }
            Button("Approve this pairing") {
                isApproving = true; failure = nil
                Task { @MainActor in
                    do {
                        try await approve(fingerprint, selected)
                        dismiss()
                    } catch {
                        failure = "Pairing was not approved. Check the fingerprint and selected conversations, then try again."
                    }
                    isApproving = false
                }
            }
            .disabled(isApproving || fingerprint.utf8.count != 64 || selected.isEmpty || selected.count > 100)
            .accessibilityIdentifier("approvePeerPairing")
        }
        .disabled(isApproving)
        .navigationTitle("Review pairing")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancel(); dismiss() }.disabled(isApproving)
            }
        }
        .interactiveDismissDisabled(isApproving)
        .onChange(of: offer) { _, _ in fingerprint = ""; selected = []; failure = nil }
        .onDisappear { cancel() }
    }
}
#endif
