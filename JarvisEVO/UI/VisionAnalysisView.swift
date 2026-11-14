import SwiftUI

/// The sheet owns its worker through cancellation and teardown, even after it
/// disappears. Answers are observations, not automatic actions or OCR context.
struct VisionAnalysisView: View {
    @Bindable var model: AppModel
    let attachment: ChatAttachment
    let originalURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    @State private var question = "Describe the visible image in one sentence."
    @State private var submittedQuestion: String?
    @State private var session: VisionSession?
    @State private var work: Task<Void, Never>?
    @State private var working = false
    @State private var progress: Double?
    @State private var error: String?
    @State private var stopping = false

    var body: some View {
        NavigationStack {
            Form {
                Section(attachment.name) {
                    Text("Analyze the image pixels on this iPhone. The model can misidentify details; check important observations against the image.")
                    if !VisionServices.nativeAvailable {
                        Text("The installed build does not include the native vision runtime. A vision-enabled build is required.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Vision model") {
                    Text("SmolVLM2 2.2B · Apache-2.0 · 1.98 GB download")
                    Text("Download once to use offline. Model setup needs additional free space for verified installation.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Download or verify vision model") { install() }
                        .disabled(working || stopping || !VisionServices.nativeAvailable || !model.canBeginHeavyWork)
                    if let progress { ProgressView(value: progress) }
                }
                Section("Ask about this image") {
                    TextField("Question", text: $question, axis: .vertical).lineLimit(2...5)
                        .disabled(working || stopping)
                    Button("Analyze image", systemImage: "eye") { analyze() }
                        .disabled(working || stopping || !VisionServices.nativeAvailable || !model.canBeginHeavyWork || originalURL == nil)
                    if working { ProgressView(session == nil ? "Preparing…" : "Analyzing locally…") }
                    if working || stopping {
                        Button(stopping ? "Releasing resources…" : "Cancel", role: .cancel) { Task { await stop() } }
                            .disabled(stopping)
                    }
                }
                if let answer = session?.output, let submittedQuestion {
                    Section("Image analysis") {
                        Text("Question: \(submittedQuestion)").font(.subheadline)
                            .accessibilityIdentifier("vision.result.question")
                        Text(answer).textSelection(.enabled)
                    }
                }
                if let message = error ?? session?.error { Section { Text(message).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Analyze image").navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear { Task { await stop() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await stop() } } }
        .onChange(of: model.heavyWorkLease) { _, lease in
            if lease?.id == session?.id, lease?.phase == .revoked { Task { await stop() } }
        }
    }

    private func install() {
        guard !working, !stopping else { return }
        working = true; error = nil; progress = 0
        work = Task { @MainActor in
            defer { working = false; progress = nil }
            do {
                let store = try VisionServices.store.get()
                try await store.install { value in Task { @MainActor in progress = value } }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func analyze() {
        guard !working, !stopping, let originalURL else { return }
        working = true; error = nil; session = nil
        let prompt = question
        submittedQuestion = prompt
        work = Task { @MainActor in
            defer { working = false }
            do {
                #if ORIVYN_NATIVE_VISION
                let store = try VisionServices.store.get()
                let read = Task.detached(priority: .userInitiated) { try VisionImageFile.read(originalURL) }
                let bytes = try await withTaskCancellationHandler { try await read.value } onCancel: { read.cancel() }
                try Task.checkCancellation()
                let runtime = try NativeVisionRuntime(store: store)
                let current = VisionSession(owner: model, runtime: runtime)
                session = current
                await current.run(encodedImage: bytes, question: prompt)
                #else
                error = "This build does not include the native vision runtime."
                #endif
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func stop() async {
        guard !stopping else { return }
        stopping = true
        work?.cancel()
        if let session { _ = await session.close() }
        await work?.value
        stopping = false
    }
}
