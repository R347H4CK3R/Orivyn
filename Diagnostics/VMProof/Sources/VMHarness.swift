import SwiftUI
import WebKit
import Observation

@MainActor
final class VMAssetHandler: NSObject, @preconcurrency WKURLSchemeHandler {
    private let store: VMAssetStore
    var active = true
    init(store: VMAssetStore) { self.store = store }
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard active else { task.didFailWithError(VMPolicyError.rejected); return }
        do {
            let (data, mime) = try store.response(for: task.request)
            print("VM_PROOF asset served: \(task.request.url?.lastPathComponent ?? "none") \(data.count) bytes")
            guard let url = task.request.url else { throw VMPolicyError.rejected }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime, "Content-Length": String(data.count), "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"])!
            task.didReceive(response); task.didReceive(data); task.didFinish()
        } catch { print("VM_PROOF asset rejected"); task.didFailWithError(VMPolicyError.rejected) }
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) { /* Synchronous immutable response has no pending IO. */ }
}

@MainActor @Observable
final class VMHarnessController: NSObject, @preconcurrency WKScriptMessageHandler, @preconcurrency WKNavigationDelegate, @preconcurrency WKUIDelegate {
    private(set) var webView: WKWebView?
    private(set) var status = "Stopped. BIOS-only prototype; no guest desktop installed."
    private(set) var instructions: UInt64 = 0
    private var owner: UUID?
    private var handler: VMAssetHandler?
    private var initialURL: URL?
    private var proofDeadline: Task<Void, Never>?

    func start() {
        guard webView == nil, owner == nil else { return }
        do {
            let root = Bundle.main.resourceURL!.appendingPathComponent("Assets", isDirectory: true)
            let store = try VMAssetStore(root: root)
            let identity = UUID(); owner = identity; instructions = 0
            let handler = VMAssetHandler(store: store); self.handler = handler
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.setURLSchemeHandler(handler, forURLScheme: "orivyn-vm")
            configuration.userContentController.add(self, name: "vmStatus")
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.navigationDelegate = self; view.uiDelegate = self
            view.isInspectable = false
            webView = view
            initialURL = URL(string: "orivyn-vm://bundle/index.html#" + identity.uuidString)!
            status = "Loading local BIOS and WebAssembly…"
            view.load(URLRequest(url: initialURL!))
            proofDeadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self, self.owner == identity else { return }
                self.stop(); self.status = "60-second BIOS proof limit reached. Start again explicitly."
            }
        } catch { stop(); status = "Local asset validation failed. Nothing started." }
    }
    func stop() {
        proofDeadline?.cancel(); proofDeadline = nil
        owner = nil; initialURL = nil; handler?.active = false; handler = nil
        let old = webView; webView = nil
        old?.configuration.userContentController.removeScriptMessageHandler(forName: "vmStatus")
        old?.stopLoading(); old?.navigationDelegate = nil; old?.uiDelegate = nil
        old?.removeFromSuperview()
        // Replace the document and release ownership; this is not proof of immediate
        // WebContent-process memory reclamation. Device measurement remains required.
        old?.loadHTMLString("", baseURL: nil)
        status = "Stopped. WebKit teardown requested; no guest state saved."
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("VM_PROOF event boundary: main=\(message.frameInfo.isMainFrame), scheme=\(message.frameInfo.securityOrigin.protocol), host=\(message.frameInfo.securityOrigin.host), owned=\(message.webView === webView)")
        guard let owner, message.webView === webView, message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "orivyn-vm",
              message.frameInfo.securityOrigin.host == "bundle",
              let value = VMStatus.parse(message.body, owner: owner) else { return }
        print("VM_PROOF accepted event: \(value.event.rawValue), instructions: \(value.instructions)")
        instructions = value.instructions
        switch value.event {
        case .ready: status = "BIOS initialized; starting actual emulated CPU."
        case .running: status = "Actual BIOS running. No operating-system guest installed."
        case .stopped: stop()
        case .error: stop(); status = "Emulator failed. No saved state or external fallback."
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = self.webView === webView && owner != nil && action.request.url == initialURL
            && action.targetFrame?.isMainFrame == true && !action.shouldPerformDownload
        print("VM_PROOF initial navigation allowed: \(allowed)")
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
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
        webView.evaluateJavaScript("JSON.stringify({state:document.readyState,vm:typeof V86,controller:typeof OfflineVM,wasm:typeof WebAssembly,stop:typeof window.orivynStop})") { value, error in
            print("VM_PROOF local document capabilities: \(value as? String ?? "unavailable"), evaluation failed: \(error != nil)")
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView else { return }
        print("VM_PROOF committed navigation failure: \((error as NSError).domain) \((error as NSError).code)")
        stop(); status = "Local document failed. No network fallback."
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard self.webView === webView else { return }; stop(); status = "WebContent ended. Start again explicitly; no state was saved."
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
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            VStack {
                Text("Orivyn native BIOS proof").font(.headline)
                Text(controller.status).accessibilityIdentifier("vm.status")
                Text(String(controller.instructions)).accessibilityIdentifier("vm.instructions")
                HStack {
                    Button("Start BIOS") { controller.start() }.disabled(controller.webView != nil).accessibilityIdentifier("vm.start")
                    Button("Stop") { controller.stop() }.disabled(controller.webView == nil).accessibilityIdentifier("vm.stop")
                }
                if let view = controller.webView { VMWebSurface(webView: view).accessibilityIdentifier("vm.surface") }
                Spacer(minLength: 0)
                Text("No guest ISO, networking, persistence, app bridge or external computer. Physical iPhone performance is unverified.").font(.caption)
            }.padding()
            .onChange(of: phase) { _, phase in if phase != .active { controller.stop() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in controller.stop() }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { controller.stop() }
            }
        }
    }
}
