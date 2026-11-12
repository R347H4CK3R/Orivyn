import SwiftUI
import ImagePlayground

/// Explicit, user-controlled image creation. Never calls a text provider or mutates the composer.
struct ImageCreationView: View {
    let stager: GeneratedImageStaging
    /// Called synchronously after staging. The recipient immediately registers ownership,
    /// imports/validates the image, and discards this URL after success or failure.
    let onAccepted: (URL, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @State private var concept = ""
    @State private var submittedConcept = ""
    @State private var showPlayground = false
    @State private var error: String?

    private var available: Bool {
        ImageCreationAvailability.isAvailable(supportsImagePlayground: supportsImagePlayground,
            osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Create an image")
                        .font(.headline)
                        .accessibilityIdentifier("image.creation.title")
                    Text("Describe the image you want. Apple Image Playground opens only when you tap Create image.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $concept)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Image description")
                        .accessibilityIdentifier("image.creation.prompt")
                    Text("\(concept.utf8.count) / 1,024 bytes")
                        .font(.caption).foregroundStyle(.secondary)
                    if !concept.isEmpty && !ImageCreationAvailability.isValidConcept(concept) {
                        Text("Enter a description of up to 1,024 UTF-8 bytes, without null characters.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Section {
                    if !available {
                        Text("On-device image creation is unavailable here. This feature requires iOS 26 and supported Apple Image Playground settings. Later iOS versions are not enabled for this on-device-only feature. You can still browse or import images.")
                            .font(.subheadline)
                            .accessibilityIdentifier("image.creation.unavailable")
                    } else {
                        Text("Uses Apple's animation, illustration and sketch styles. External image providers are not offered. Only an image you accept is saved to Orivyn.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Create image") {
                        guard available, ImageCreationAvailability.isValidConcept(concept) else { return }
                        submittedConcept = concept
                        showPlayground = true
                    }
                    .disabled(!available || !ImageCreationAvailability.isValidConcept(concept) || showPlayground)
                    .accessibilityIdentifier("image.creation.generate")
                }
            }
            .navigationTitle("Create image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("image.creation.cancel")
                }
            }
        }
        .imagePlaygroundSheet(isPresented: $showPlayground, concept: submittedConcept, sourceImage: nil,
            onCompletion: { url in
                // Copy now, before returning from the system callback. Do not defer this URL.
                do {
                    let owned = try stager.stage(from: url)
                    onAccepted(owned, submittedConcept)
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                }
            }, onCancellation: {
                // The system dismisses its sheet; the editable concept remains unchanged.
            })
        .imagePlaygroundGenerationStyle(.illustration, in: [.animation, .illustration, .sketch])
        .alert("Could not save generated image", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}
