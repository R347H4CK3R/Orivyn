#if ORIVYN_PEER_TLS_SPIKE && canImport(Network) && canImport(Security) && canImport(CryptoKit) && canImport(X509) && os(iOS)
import SwiftUI
import UIKit

/// Foreground-only development candidate. Never visible in a normal build.
struct PeerSyncSettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Group {
            if let session = model.peerSyncSession {
                PeerSyncSetupView(model: model, session: session)
            } else { ProgressView().task { model.preparePeerSyncSettings() } }
        }
        .navigationTitle("Nearby text sync")
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            model.peerSyncSession?.setProtectedDataAvailable(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            model.peerSyncSession?.setProtectedDataAvailable(true)
        }
    }
}

private struct PeerSyncSetupView: View {
    @Bindable var model: AppModel
    @Bindable var session: PeerSyncSession
    @State private var selected = Set<UUID>()
    @State private var pastedOffer = ""
    @State private var host = ""
    @State private var port = "49152"
    @State private var direction: PeerSyncSession.Direction = .send
    @State private var reviewPresented = false
    @State private var failure: String?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                Text("Development candidate: nearby text only. Both apps must be open and unlocked. Device testing is incomplete.")
                Text("No cloud account or automatic discovery. Pairing and each direction need explicit approval. Trust is not restored after restarting the app.")
                Text("Orivyn uses your local network when you connect to a plugin server or enable approved nearby text sync. Nearby sync automatically exchanges only selected, complete, attachment-free conversations with your verified device while Orivyn is open and unlocked.")
            }
            if session.approval == nil {
                Section("Prepare this device") {
                    Picker("Direction", selection: $direction) {
                        ForEach(PeerSyncSession.Direction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.disabled(session.pendingOffer != nil)
                    if direction == .send {
                    ForEach(model.conversations) { conversation in
                        Toggle(conversation.title, isOn: Binding(get: { selected.contains(conversation.id) },
                            set: { value in
                                if value { selected.insert(conversation.id) }
                                else { selected.remove(conversation.id) }
                            })).disabled(session.pendingOffer != nil)
                    }
                    }
                    Text("Only selected titles and identifiers are included in your pairing document. Conversation contents are not included.")
                        .font(.caption)
                    Button(session.localFingerprint.isEmpty ? "Create pairing document" : "Create updated pairing document") {
                        run {
                            try await session.prepareOffer(conversations: model.conversations,
                                sourceIDs: direction == .send ? selected : [])
                        }
                    }.disabled(working || selected.count > 100)
                    if !session.localFingerprint.isEmpty {
                        Text("This device’s fingerprint").font(.headline)
                        Text(session.localFingerprint).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if !session.localOfferText.isEmpty {
                        ShareLink("Share pairing document", item: session.localOfferText)
                        Text("Share directly with the other device. It includes a public certificate, destination identity and selected conversation titles. It contains no private key.")
                            .font(.caption)
                    }
                }
                Section("Review the other device") {
                    Text("The first device creates and shares a document. The second imports it, then creates and shares an updated document back. After both devices have imported each other’s documents, verify fingerprints and approve the selected direction. Enable the receiving device first.")
                        .font(.caption)
                    TextEditor(text: $pastedOffer).frame(minHeight: 100)
                        .accessibilityLabel("Other device’s pairing document")
                        .disabled(session.pendingOffer != nil)
                    if direction == .send {
                        TextField("Other device’s local address", text: $host)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .disabled(session.pendingOffer != nil)
                    }
                    TextField("Port", text: $port).keyboardType(.numberPad).disabled(session.pendingOffer != nil)
                    Button("Import pairing document") {
                        do {
                            try session.review(text: pastedOffer, direction: direction, host: host, port: port)
                            failure = nil
                        } catch { failure = "Unable to review this pairing document or address. Create this device’s document first and check the other device’s details." }
                    }.disabled(working || session.localFingerprint.isEmpty || session.pendingOffer != nil)
                    if session.pendingOffer != nil {
                        Text("Document imported. If you are the second device, create and share the updated reply above before approving.")
                            .font(.caption)
                        Button("Verify fingerprint and approve") { reviewPresented = true }
                        Button("Cancel pending review") { session.cancelReview() }
                    }

                }
            } else {
                Section("Approved direction") {
                    Text(session.direction.rawValue)
                    Text(session.endpointDescription)
                    Text("\(session.approval?.approvedSourceIDs.count ?? 0) conversations")
                    Toggle("Enable while open and unlocked", isOn: Binding(get: { session.enabled }, set: session.setEnabled))
                    TimelineView(.periodic(from: .now, by: 1)) { _ in Text(session.status).font(.caption) }
                    if let listeningPort = session.listeningPort {
                        Text("Listening on port \(listeningPort)").font(.caption)
                    }
                    Button("Retry stopped exchange") { session.retry() }.disabled(!session.enabled)
                }
            }
            Section {
                Text("Only complete, attachment-free conversations are supported; selecting an attachment or unfinished message stops the exchange. Memories, credentials and other conversations are excluded. Conflicting local edits are preserved as separate versions. Deletions are not propagated.")
                    .font(.caption)
                Button("Revoke pairing", role: .destructive) {
                    Task { await session.revoke() }
                }.disabled(session.revoking)
                if let failure = session.failure { Text(failure).foregroundStyle(.red) }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
        }
        .sheet(isPresented: $reviewPresented) {
            if let offer = session.pendingOffer {
                NavigationStack {
                    VStack {
                        Text(session.direction.rawValue + " · " + session.endpointDescription).font(.headline).padding()
                        Text("Compare the destination and conversation identifiers on the other device. Imported titles are untrusted proposals.")
                            .font(.caption).padding(.horizontal)
                        Text("Destination: " + (session.direction == .receive
                            ? session.localEpoch?.uuidString ?? "Unavailable"
                            : offer.receiverEpoch?.uuidString ?? "Unavailable"))
                            .font(.caption.monospaced()).textSelection(.enabled)
                        PeerPairingReviewView(offer: offer, localFingerprint: session.localFingerprint,
                            conversations: choices(offer),
                            approve: { fingerprint, ids in
                                try await session.approve(fingerprint: fingerprint, sourceIDs: ids)
                            }, cancel: { session.cancelReview() })
                    }
                }
            }
        }
    }

    private func choices(_ offer: PeerPairingOffer) -> [PeerPairingReviewView.ConversationChoice] {
        if session.direction == .receive {
            return offer.offeredConversations.map { .init(id: $0.id, title: $0.title) }
        }
        return model.conversations.filter { selected.contains($0.id) }.map { .init(id: $0.id, title: $0.title) }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !working else { return }
        working = true; failure = nil
        Task { @MainActor in
            defer { working = false }
            do { try await operation() }
            catch { failure = "Setup did not complete. Keep both apps active and unlocked, then try again." }
        }
    }
}
#endif
