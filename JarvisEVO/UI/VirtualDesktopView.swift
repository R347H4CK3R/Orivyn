import SwiftUI

/// Phone-contained Linux guest. No network adapter or host-file bridge is exposed.
struct VirtualDesktopView: View {
    @Bindable var model: AppModel
    @State private var controller: VMHarnessController
    @State private var session: VirtualDesktopSession
    @State private var input = ""
    @State private var sendingInput = false
    @State private var inputError: String?
    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel) {
        self.model = model
        let runtime = VMHarnessController(checkpointDirectory: model.virtualDesktopDirectory)
        _controller = State(initialValue: runtime)
        _session = State(initialValue: VirtualDesktopSession(model: model, runtime: runtime))
    }
    private var available: Bool {
        session.phase == .running && controller.canInteract && !controller.isDrainingCheckpoint && !controller.checkpointBusy
            && model.heavyWorkLease?.id == session.id && model.heavyWorkLease?.phase == .ready
    }
    private func viewportHeight(in size: CGSize) -> CGFloat {
        // Compact-height fallback: preserve 180pt of guest pixels and scroll the
        // whole workspace when the keyboard/landscape leaves less space. Never
        // compress the guest to a percentage of a near-zero remaining height.
        // Exception: very narrow windows retain the guest's 4:3 aspect ratio.
        let availableHeight = max(0, size.height - 32)
        return min(max(0, size.width - 32) * 0.75, max(180, availableHeight * 0.45))
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 8) {
                    // Reserve guest pixels before laying out controls. A flexible WKWebView
                    // in a non-scrolling stack otherwise collapses under the keyboard/logs.
                    if let view = controller.webView {
                        VMWebSurface(webView: view)
                            .frame(height: viewportHeight(in: geometry.size))
                            .clipped()
                            .accessibilityIdentifier("desktop.surface")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(controller.status).font(.caption).accessibilityIdentifier("desktop.status")
                        if let error = session.error { Text(error).font(.caption).foregroundStyle(.orange) }
                        TextField("Text to type in the guest", text: $input)
                            .focused($inputFocused)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("desktop.input")
                        HStack {
                            Button("Send line") {
                                inputFocused = false
                                let submitted = input
                                inputError = nil
                                sendingInput = true
                                controller.sendInput(submitted + "\n") { accepted in
                                    sendingInput = false
                                    if accepted && input == submitted { input = "" }
                                    if !accepted { inputError = "Input was not delivered. Your text is kept; check guest readiness and the keyboard limits." }
                                }
                            }
                                .disabled(!available || !controller.canType || sendingInput || input.isEmpty).accessibilityIdentifier("desktop.input.send")
                            Button("Enter") { inputFocused = false; controller.sendInput("\n") }.disabled(!available || !controller.canType || sendingInput)
                        }
                        if let inputError { Text(inputError).font(.caption2).foregroundStyle(.orange) }
                        Text("Guest keyboard accepts up to 1,023 ASCII characters per line. Rejected input stays here.").font(.caption2)
                        HStack {
                            Button("Save") { inputFocused = false; controller.checkpoint(restore: false) }.disabled(!available).accessibilityIdentifier("desktop.checkpoint.save")
                            Button("Restore") { inputFocused = false; controller.checkpoint(restore: true) }.disabled(!available)
                            Button("Resume") { inputFocused = false; controller.resume() }.disabled(!available || controller.runtimePhase != "paused")
                        }
                        Text(controller.checkpointStatus).font(.caption2).accessibilityIdentifier("desktop.checkpoint.status")
                        DisclosureGroup("Live diagnostics") {
                            ScrollView {
                                Text(controller.diagnostics)
                                    .font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                                Text(controller.guestConsole).font(.system(.caption2, design: .monospaced)).accessibilityIdentifier("desktop.console")
                            }.frame(maxHeight: 150)
                        }
                        Text("Runs locally inside Orivyn. No internet or access to other iPhone apps. Save before closing; restoration requires explicit Resume.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("desktop.controls")
        }
        .navigationTitle("Virtual desktop")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide keyboard") { inputFocused = false }
                    .accessibilityIdentifier("desktop.keyboard.hide")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") {
                    Task { if await session.close() { dismiss() } }
                }.disabled(session.phase == .stopping).accessibilityIdentifier("desktop.close")
            }
        }
        .task { session.start() }
        .onDisappear { Task { await session.close() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await session.close() } }
        }
        .onChange(of: model.heavyWorkLease?.phase) { _, phase in
            if model.heavyWorkLease?.id == session.id, phase == .revoked {
                Task { await session.close() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task { await session.close() }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
                Task { await session.close() }
            }
        }
    }
}
