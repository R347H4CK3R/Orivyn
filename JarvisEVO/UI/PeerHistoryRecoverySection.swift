import SwiftUI

/// The retained receive owner is released only by a successful database reload.
/// This action never retries a transfer or grants pairing/network permission.
struct PeerHistoryRecoverySection: View {
    @Bindable var model: AppModel
    @State private var recoveryError: String?

    var body: some View {
        if model.needsPeerHistoryRecovery {
            Section("Reload received history") {
                Text("A received transfer may have been saved, but its history could not be reloaded. Editing is paused to protect your data. Your unsent draft and attachments are kept.")
                    .font(.caption)
                Button {
                    guard !model.isRecoveringPeerHistory else { return }
                    recoveryError = nil
                    Task { @MainActor in
                        do { try await model.recoverPeerHistoryReceive() }
                        catch {
                            recoveryError = "History is still unavailable. Editing remains paused. Retry when storage is available; do not delete your data."
                        }
                    }
                } label: {
                    if model.isRecoveringPeerHistory { ProgressView("Reloading history") }
                    else { Text("Reload received history") }
                }
                .disabled(model.isRecoveringPeerHistory)
                .accessibilityIdentifier("peerHistory.recover")
                if let recoveryError { Text(recoveryError).font(.caption).foregroundStyle(.red) }
            }
            .accessibilityIdentifier("peerHistory.recovery")
        }
    }
}
