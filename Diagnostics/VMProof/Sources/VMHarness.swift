import SwiftUI
import WebKit
import Observation
import CryptoKit

@MainActor
final class VMAssetHandler: NSObject, @preconcurrency WKURLSchemeHandler {
    private let store: VMAssetStore
    var active = true
    let record: (String) -> Void
    init(store: VMAssetStore, record: @escaping (String) -> Void) { self.store = store; self.record = record }
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard active else { task.didFailWithError(VMPolicyError.rejected); return }
        do {
            let (data, mime) = try store.response(for: task.request)
            record("asset served: \(task.request.url?.lastPathComponent ?? "none") \(data.count) bytes")
            guard let url = task.request.url else { throw VMPolicyError.rejected }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime, "Content-Length": String(data.count), "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"])!
            task.didReceive(response); task.didReceive(data); task.didFinish()
        } catch { record("asset rejected"); task.didFailWithError(VMPolicyError.rejected) }
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) { /* Synchronous immutable response has no pending IO. */ }
}

@MainActor @Observable
final class VMHarnessController: NSObject, @preconcurrency WKScriptMessageHandler, @preconcurrency WKNavigationDelegate, @preconcurrency WKUIDelegate {
    private(set) var webView: WKWebView?
    private(set) var status = "Stopped. Internal maintained guest proof; native acceptance pending."
    private(set) var instructions: UInt64 = 0
    private(set) var diagnostics = ""
    private(set) var guestConsole = ""
    private func record(_ text: String) {
        diagnostics = String((diagnostics + "\n" + text).suffix(4096))
    }
    private(set) var checkpointStatus = "Checkpoint not yet saved."
    private(set) var checkpointBusy = false
    private var checkpointBridge: VMCheckpointBridge?
    // One actor serializes this directory across every WebKit owner.
    private var checkpointStore: VMCheckpointStore?
    private var checkpointDrain: Task<Void, Never>?
    private(set) var isDrainingCheckpoint = false
    private var owner: UUID?
    private var handler: VMAssetHandler?
    private var initialURL: URL?
    private var proofDeadline: Task<Void, Never>?

    func start() {
        guard webView == nil, owner == nil, !isDrainingCheckpoint else { return }
        do {
            let root = Bundle.main.resourceURL!.appendingPathComponent("Assets", isDirectory: true)
            let store = try VMAssetStore(root: root)
            let identity = UUID(); owner = identity; instructions = 0
            diagnostics = "Owner created"
            let handler = VMAssetHandler(store: store) { [weak self] in self?.record($0) }; self.handler = handler
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.setURLSchemeHandler(handler, forURLScheme: "orivyn-vm")
            configuration.userContentController.add(self, name: "vmStatus")
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("VMGuestProofCheckpoints", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            let checkpointStore: VMCheckpointStore
            if let existing = self.checkpointStore { checkpointStore = existing }
            else {
                checkpointStore = try VMCheckpointStore(root: directory)
                self.checkpointStore = checkpointStore
            }
            let configurationDigest = SHA256.hash(data: Data("maintained;ram=134217728;vga=8388608;network=none;disk=0897e5f867267c209f2866e2ee960971caf25886eb0345fe2f514b11e19cf0f1;schema=1".utf8)).map { String(format: "%02x", $0) }.joined()
            func assetGroupDigest(_ names: Set<String>) -> String {
                let text = VMAssetCatalog.files.filter { names.contains($0.name) }.sorted { $0.name < $1.name }.map { $0.name + ":" + $0.sha256 }.joined(separator: "\n")
                return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            }
            let checkpointIdentity = VMCheckpointIdentity(engineSHA256: assetGroupDigest(["libv86.js", "v86.wasm", "v86-fallback.wasm"]),
                guestSHA256: assetGroupDigest(["seabios.bin", "vgabios.bin", "maintained.img"]), configurationSHA256: configurationDigest)
            let bridge = VMCheckpointBridge(owner: identity, identity: checkpointIdentity, store: checkpointStore)
            checkpointBridge = bridge
            configuration.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "vmCheckpoint")
            let identityJSON = String(data: try JSONEncoder().encode(checkpointIdentity), encoding: .utf8)!
            configuration.userContentController.addUserScript(WKUserScript(source: "window.orivynCheckpointIdentity=Object.freeze(" + identityJSON + ");", injectionTime: .atDocumentStart, forMainFrameOnly: true))
            let view = WKWebView(frame: .zero, configuration: configuration)
            bridge.ownedWebView = view
            view.navigationDelegate = self; view.uiDelegate = self
            view.isInspectable = false
            webView = view
            initialURL = URL(string: "orivyn-vm://bundle/index.html#" + identity.uuidString)!
            status = "Loading pinned local guest, BIOS and WebAssembly…"
            view.load(URLRequest(url: initialURL!))
            proofDeadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(180)) } catch { return }
                guard let self, self.owner == identity else { return }
                self.stop(); self.status = "180-second guest proof limit reached. Start again explicitly."
            }
        } catch { stop(); status = "Local asset validation failed. Nothing started." }
    }
    func stop() {
        proofDeadline?.cancel(); proofDeadline = nil
        if checkpointBusy { checkpointStatus = "Checkpoint interrupted. Previously committed state is retained." }
        if let bridge = checkpointBridge {
            let drain = bridge.invalidate()
            isDrainingCheckpoint = true
            checkpointDrain = Task { @MainActor [weak self] in
                await drain.value
                guard let self else { return }
                self.isDrainingCheckpoint = false
                self.checkpointDrain = nil
            }
        }
        checkpointBridge = nil; checkpointBusy = false
        owner = nil; initialURL = nil; handler?.active = false; handler = nil
        let old = webView; webView = nil
        old?.configuration.userContentController.removeScriptMessageHandler(forName: "vmStatus")
        old?.configuration.userContentController.removeScriptMessageHandler(forName: "vmCheckpoint", contentWorld: .page)
        old?.stopLoading(); old?.navigationDelegate = nil; old?.uiDelegate = nil
        old?.removeFromSuperview()
        // Replace the document and release ownership; this is not proof of immediate
        // WebContent-process memory reclamation. Device measurement remains required.
        old?.loadHTMLString("", baseURL: nil)
        status = "Stopped. WebKit teardown requested; previous checkpoints retained."
    }
    func checkpoint(restore: Bool) {
        guard let view = webView, let identity = owner, !checkpointBusy else { return }
        checkpointBusy = true
        checkpointStatus = restore ? "Verifying and loading checkpoint…" : "Pausing and saving verified checkpoint…"
        let script = restore ? "const value=await window.orivynRestoreCheckpoint(); return value === null ? 'missing' : 'restored';" : "await window.orivynSaveCheckpoint(); return 'saved';"
        view.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self, weak view] result in
            guard let self, self.owner == identity, self.webView === view else { return }
            self.checkpointBusy = false
            switch result {
            case .success(let value):
                switch value as? String {
                case "saved": self.checkpointStatus = "Checkpoint verified and saved. Guest CPU is paused."
                case "restored": self.checkpointStatus = "Checkpoint verified and restored. Tap Resume."
                case "missing": self.checkpointStatus = "No compatible checkpoint saved."
                default: self.checkpointStatus = "Unexpected checkpoint response; no success claimed."
                }
            case .failure: self.checkpointStatus = "Checkpoint failed. Previous saved state is retained."
            }
        }
    }
    func diagnosticConsole() {
        guard !checkpointBusy, let view = webView else { return }
        view.callAsyncJavaScript("await window.orivynDiagnosticConsole();", arguments: [:], in: nil, in: .page) { _ in }
    }
    func sendInput(_ text: String) {
        guard !checkpointBusy, let view = webView, let identity = owner else { return }
        view.callAsyncJavaScript("await window.orivynType(text);", arguments: ["text": text], in: nil, in: .page) { [weak self, weak view] result in
            guard let self, self.owner == identity, self.webView === view else { return }
            switch result {
            case .success: self.record("Guest keyboard input delivered; application action not verified.")
            case .failure: self.record("Guest keyboard input rejected by runtime state or bounds.")
            }
        }
    }
    func resume() {
        guard !checkpointBusy, let view = webView, let identity = owner else { return }
        view.callAsyncJavaScript("await window.orivynResume();", arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, self.owner == identity else { return }
            if case .failure = result { self.checkpointStatus = "Resume was not accepted. Check the current runtime state." }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        record("event boundary: main=\(message.frameInfo.isMainFrame), scheme=\(message.frameInfo.securityOrigin.protocol), host=\(message.frameInfo.securityOrigin.host), owned=\(message.webView === webView)")
        guard let owner, message.webView === webView, message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "orivyn-vm",
              message.frameInfo.securityOrigin.host == "bundle",
              let value = VMStatus.parse(message.body, owner: owner) else { return }
        record("accepted event: \(value.event.rawValue), instructions: \(value.instructions)")
        instructions = value.instructions
        switch value.event {
        case .diagnostic:
            let text = value.diagnostic ?? "Missing diagnostic"
            if text.hasPrefix("guest serial: ") { guestConsole = String((guestConsole + text.dropFirst(14)).suffix(2048)) }
            else { record(text) }
        case .ready: status = "Guest machine initialized; starting emulated CPU."
        case .paused: status = "Guest CPU paused. Resume explicitly; checkpoint result is shown separately."
        case .running: status = "Guest CPU running. Desktop readiness has not been verified."
        case .stopped: stop()
        case .error: stop(); status = "Emulator failed. No saved state or external fallback."
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let allowed = self.webView === webView && owner != nil && action.request.url == initialURL
            && action.targetFrame?.isMainFrame == true && !action.shouldPerformDownload
        record("initial navigation allowed: \(allowed)")
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(self.webView === webView && response.isForMainFrame && response.canShowMIMEType
            && isInitialDocument(response.response.url) ? .allow : .cancel)
    }
    private func isInitialDocument(_ url: URL?) -> Bool {
        guard let url, let initialURL, var incoming = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var expected = URLComponents(url: initialURL, resolvingAgainstBaseURL: false) else { return false }
        incoming.fragment = nil; expected.fragment = nil
        return incoming == expected
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView, owner != nil else { return }
        // Inspect only fixed local runtime capabilities, not page/user data.
        webView.evaluateJavaScript("JSON.stringify({state:document.readyState,vm:typeof V86,controller:typeof OfflineVM,wasm:typeof WebAssembly,stop:typeof window.orivynStop})") { [weak self] value, error in
            self?.record("local document capabilities: \(value as? String ?? "unavailable"), evaluation failed: \(error != nil)")
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView else { return }
        record("committed navigation failure: \((error as NSError).domain) \((error as NSError).code)")
        stop(); status = "Local document failed. No network fallback."
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard self.webView === webView else { return }; stop(); status = "WebContent ended. Start again explicitly; unsaved changes were lost."
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView else { return }; stop(); status = "Local WebKit load failed. No network fallback."
    }
}

struct VMWebSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: ()) { view.stopLoading(); view.removeFromSuperview() }
}

@main
struct VMHarnessApp: App {
    @State private var controller = VMHarnessController()
    @State private var guestInput = ""
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            VStack {
                Text("Orivyn internal guest proof").font(.headline)
                Text(controller.status).accessibilityIdentifier("vm.status")
                Text(controller.diagnostics).font(.caption2).lineLimit(5).accessibilityIdentifier("vm.diagnostics")
                Text(controller.guestConsole).font(.caption2).lineLimit(3).accessibilityIdentifier("vm.console")
                Text(String(controller.instructions)).accessibilityIdentifier("vm.instructions")
                HStack {
                    Button("Start guest") { controller.start() }.disabled(controller.webView != nil || controller.isDrainingCheckpoint).accessibilityIdentifier("vm.start")
                    Button("Stop") { controller.stop() }.disabled(controller.webView == nil).accessibilityIdentifier("vm.stop")
                }
                Text(controller.checkpointStatus).font(.caption).accessibilityIdentifier("vm.checkpoint.status")
                HStack {
                    Button("Save checkpoint") { controller.checkpoint(restore: false) }.accessibilityIdentifier("vm.checkpoint.save")
                    Button("Restore") { controller.checkpoint(restore: true) }.accessibilityIdentifier("vm.checkpoint.restore")
                    Button("Resume") { controller.resume() }.accessibilityIdentifier("vm.resume")
                }.disabled(controller.webView == nil || controller.checkpointBusy)
                HStack {
                    TextField("Guest keyboard text", text: $guestInput).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("vm.input")
                    Button("Send line") { controller.sendInput(guestInput + "\n"); guestInput = "" }.disabled(controller.webView == nil || controller.checkpointBusy || guestInput.isEmpty).accessibilityIdentifier("vm.input.send")
                    Button("Console") { controller.diagnosticConsole() }.accessibilityIdentifier("vm.console.switch")
                    Button("Enter") { controller.sendInput("\n") }.disabled(controller.webView == nil || controller.checkpointBusy).accessibilityIdentifier("vm.input.enter")
                }
                if let view = controller.webView { VMWebSurface(webView: view).accessibilityIdentifier("vm.surface") }
                Spacer(minLength: 0)
                Text("Internal offline guest test. No network, host files or external computer. Desktop interaction, checkpoint and iPhone performance require verification.").font(.caption)
            }.padding()
            .onChange(of: phase) { _, phase in if phase != .active { controller.stop() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in controller.stop() }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { controller.stop() }
            }
        }
    }
}
