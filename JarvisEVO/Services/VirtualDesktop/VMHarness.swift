import SwiftUI
import WebKit
import Observation
import CryptoKit
#if DEBUG
import OSLog
#endif

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
    private let configuredCheckpointDirectory: URL?
    init(checkpointDirectory: URL? = nil) {
        configuredCheckpointDirectory = checkpointDirectory
        super.init()
    }
    private(set) var webView: WKWebView?
    private(set) var status = "Stopped. Start the local virtual desktop to begin."
    private(set) var runtimePhase = "idle"
    private(set) var instructions: UInt64 = 0
    private(set) var diagnostics = ""
    private(set) var guestConsole = ""
    private func record(_ text: String) {
        diagnostics = String((diagnostics + "\n" + Date.now.formatted(.iso8601) + " " + text).suffix(4096))
    }
    private(set) var checkpointStatus = "Checkpoint not yet saved."
    private(set) var checkpointBusy = false
    private var checkpointBridge: VMCheckpointBridge?
    // One actor serializes this directory across every WebKit owner.
    private var checkpointStore: VMCheckpointStore?
    private var checkpointDrain: Task<Void, Never>?
    private var teardown = VMTeardownCoordinator()
    private var webProcessEnded = false
    private(set) var isDrainingCheckpoint = false
    private var owner: UUID?
    private var handler: VMAssetHandler?
    private var initialURL: URL?


    var canInteract: Bool { owner != nil && webView != nil && !isDrainingCheckpoint && ["running", "paused"].contains(runtimePhase) }
    var canType: Bool { canInteract && runtimePhase == "running" && !checkpointBusy }

    var canStart: Bool {
        webView == nil && owner == nil && !isDrainingCheckpoint && teardown.phase != .failed
    }

    func start() {
        guard canStart else { return }
        teardown = VMTeardownCoordinator(); webProcessEnded = false
        do {
            let root = Bundle.main.resourceURL!.appendingPathComponent("VMAssets", isDirectory: true)
            let store = try VMAssetStore(root: root)
            let identity = UUID(); owner = identity; instructions = 0; runtimePhase = "preparing"
            diagnostics = "Owner created"
            let handler = VMAssetHandler(store: store) { [weak self] in self?.record($0) }; self.handler = handler
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.setURLSchemeHandler(handler, forURLScheme: "orivyn-vm")
            configuration.userContentController.add(self, name: "vmStatus")
            let directory = try configuredCheckpointDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("VirtualDesktopCheckpoints", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            let checkpointStore: VMCheckpointStore
            if let existing = self.checkpointStore { checkpointStore = existing }
            else {
                checkpointStore = try VMCheckpointStore(root: directory)
                self.checkpointStore = checkpointStore
            }
            let configurationDigest = SHA256.hash(data: Data("maintained;ram=134217728;vga=8388608;network=none;disk=78418639ecd90573da211b62a502334f569f029b913525f50601b09d928b244d;schema=1".utf8)).map { String(format: "%02x", $0) }.joined()
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

        } catch { stop(); status = "Local asset validation failed. Nothing started." }
    }
    func stop() {
        guard !isDrainingCheckpoint else { return }
        if checkpointBusy { checkpointStatus = "Checkpoint interrupted. Previously committed state is retained." }
        let drain = checkpointBridge?.invalidate()
        checkpointBridge = nil; checkpointBusy = false
        // Immediately revoke callback/input ownership, but keep the runtime and
        // immutable asset handler alive until its pending operations settle.
        owner = nil; initialURL = nil; runtimePhase = "stopping"
        guard let old = webView else {
            handler?.active = false; handler = nil
            if let drain {
                isDrainingCheckpoint = true
                checkpointDrain = Task { @MainActor [self] in
                    await drain.value
                    isDrainingCheckpoint = false; checkpointDrain = nil
                }
            }
            return
        }
        isDrainingCheckpoint = true
        status = "Stopping: waiting for runtime and checkpoint operations…"
        let pending = teardown.stop(runtime: { [self, old] in
            if webProcessEnded { return true }
            let acknowledged: Bool = await withCheckedContinuation { continuation in
                old.callAsyncJavaScript("if (location.protocol !== 'orivyn-vm:' || location.host !== 'bundle') return false; window.orivynBootCancelled = true; if (typeof window.orivynStop !== 'function') return true; await window.orivynStop(); return true;",
                                        arguments: [:], in: nil, in: .page) { result in
                    switch result {
                    case .success(let value): continuation.resume(returning: (value as? Bool) == true)
                    case .failure: continuation.resume(returning: false)
                    }
                }
            }
            // A verified process-termination callback also ends its runtime work.
            // Missing JS or an evaluation error alone is NOT this acknowledgment.
            return acknowledged || webProcessEnded
        }, checkpoint: {
            await drain?.value
        }, detach: { [self, old] in
            handler?.active = false; handler = nil
            old.configuration.userContentController.removeScriptMessageHandler(forName: "vmStatus")
            old.configuration.userContentController.removeScriptMessageHandler(forName: "vmCheckpoint", contentWorld: .page)
            old.stopLoading(); old.navigationDelegate = nil; old.uiDelegate = nil
            old.removeFromSuperview(); old.loadHTMLString("", baseURL: nil)
            webView = nil
        })
        checkpointDrain = Task { @MainActor [self] in
            let acknowledged = await pending.value
            isDrainingCheckpoint = false
            checkpointDrain = nil
            runtimePhase = acknowledged ? "stopped" : "failed"
            status = acknowledged
                ? "Stopped. Operations drained; WebKit teardown requested. Checkpoints retained."
                : "Stop could not be verified. Restart is blocked; restart Orivyn. Checkpoints retained."
        }
    }
    /// The outer presentation owner must await this before releasing its matching
    /// AppModel heavy-work lease. False keeps the lease blocked until a verified
    /// process teardown; sheet dismissal or a JS event alone is insufficient.
    func stopAndWait() async -> Bool {
        stop()
        await checkpointDrain?.value
        return teardown.phase == .stopped || (teardown.phase == .idle && webView == nil && owner == nil)
    }

    func checkpoint(restore: Bool) {
        #if DEBUG
        Logger(subsystem: "app.jarvisevo.boundary-diagnostic", category: "checkpoint").notice("checkpoint.enter restore=\(restore) view=\(self.webView != nil) owner=\(self.owner != nil) busy=\(self.checkpointBusy)")
        #endif
        guard let view = webView, let identity = owner, !checkpointBusy else { return }
        #if DEBUG
        Logger(subsystem: "app.jarvisevo.boundary-diagnostic", category: "checkpoint").notice("checkpoint.admitted restore=\(restore)")
        #endif
        checkpointBusy = true
        checkpointStatus = restore ? "Verifying and loading checkpoint…" : "Pausing and saving verified checkpoint…"
        let script = restore ? "const value=await window.orivynRestoreCheckpoint(); return value === null ? 'missing' : 'restored';" : "await window.orivynSaveCheckpoint(); return 'saved';"
        view.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self, weak view] result in
            #if DEBUG
            Logger(subsystem: "app.jarvisevo.boundary-diagnostic", category: "checkpoint").notice("checkpoint.callback ownerMatches=\(self?.owner == identity) viewMatches=\(self?.webView === view)")
            #endif
            guard let self, self.owner == identity, self.webView === view else { return }
            self.checkpointBusy = false
            switch result {
            case .success(let value):
                // This is the historical checkpoint result. Live CPU state and
                // Resume guidance belong to status, which follows runtime events.
                switch value as? String {
                case "saved": self.checkpointStatus = "Checkpoint verified and saved."
                case "restored": self.checkpointStatus = "Checkpoint verified and restored."
                case "missing": self.checkpointStatus = "No compatible checkpoint saved."
                default: self.checkpointStatus = "Unexpected checkpoint response; no success claimed."
                }
            case .failure: self.checkpointStatus = "Checkpoint failed. Previous saved state is retained."
            }
        }
    }
    func diagnosticConsole() {
        guard !checkpointBusy, !isDrainingCheckpoint, owner != nil, let view = webView else { return }
        view.callAsyncJavaScript("await window.orivynDiagnosticConsole();", arguments: [:], in: nil, in: .page) { _ in }
    }
    func sendInput(_ text: String, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard canType, let view = webView, let identity = owner else { completion(false); return }
        view.callAsyncJavaScript("await window.orivynType(text);", arguments: ["text": text], in: nil, in: .page) { [weak self, weak view] result in
            guard let self, self.owner == identity, self.webView === view else { completion(false); return }
            switch result {
            case .success: self.record("Guest keyboard input delivered; application action not verified."); completion(true)
            case .failure: self.record("Guest keyboard input rejected by runtime state or bounds."); completion(false)
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
        case .ready: runtimePhase = "ready"; status = "Guest machine initialized; starting emulated CPU."
        case .paused: runtimePhase = "paused"; status = "Guest CPU paused. Resume explicitly; checkpoint result is shown separately."
        case .running: runtimePhase = "running"; status = "Guest CPU running. Desktop readiness has not been verified."
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
        guard self.webView === webView else { return }; webProcessEnded = true; stop(); status = "WebContent ended. Start again explicitly; unsaved changes were lost."
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

extension VMHarnessController: VirtualDesktopRuntime {
    func startRuntime() -> Bool { start(); return webView != nil && owner != nil }
}
