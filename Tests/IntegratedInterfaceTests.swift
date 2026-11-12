import XCTest
import SwiftUI
import UIKit
import WebKit
@testable import JarvisEVO

/// Native view fixtures, explicitly not generated model responses. These render
/// the actual MessageRow and its rich blocks, including the real bundled math.
@MainActor
final class IntegratedInterfaceTests: XCTestCase {
    func testActualMessageRowFixtureRendersLightTableCodeAndOfflineMath() async throws {
        try await inspectFixture(dark: false, large: false)
    }

    func testActualMessageRowFixtureRemainsBoundedInDarkAccessibilityText() async throws {
        try await inspectFixture(dark: true, large: true)
    }

    func testMenuArtworkContainsOpaqueHighContrastStrokesInBothAppearances() throws {
        for dark in [false, true] {
            let image = try XCTUnwrap(EvoMenuGlyph.image(dark: dark).cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let opaque = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0 + 3] > 240 }
            XCTAssertGreaterThan(opaque.count, image.width * image.height / 20)
            for index in opaque {
                if dark { XCTAssertGreaterThan(pixels[index], 240) }
                else { XCTAssertLessThan(pixels[index], 15) }
            }
        }
    }

    private func inspectFixture(dark: Bool, large: Bool) async throws {
        let source = """
        ## Native rendering fixture
        This is **controlled view input**, not an AI response.

        | Item | Count |
        | :--- | ---: |
        | Café | 42 |

        ```swift
        let value = 42
        print(value)
        ```

        $$\\frac{1}{2}$$
        """
        let row = MessageRow(message: ChatMessage(role: .assistant, content: source), isGenerating: false, isSpeaking: false,
            attachmentURL: { _ in nil }, attachmentPreviewURL: { _ in nil }, onCopy: {}, onReadAloud: {},
            onSelect: {}, onEdit: {}, onBranch: {}, onRegenerate: {})
        let content = ScrollView { row.padding(20) }
            .background(Color(uiColor: .systemBackground))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
        let controller = UIHostingController(rootView: content)
        // Attach the fixture to an active iOS26 scene instead of the deprecated
        // scene-less UIWindow(frame:). Native evidence will test this host hypothesis.
        let sceneDeadline = ContinuousClock.now + .seconds(10)
        var activeScene: UIWindowScene?
        repeat {
            activeScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if activeScene != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < sceneDeadline
        let sceneEvidence = XCTAttachment(string: sceneDescription())
        sceneEvidence.name = "Native fixture scene setup"
        sceneEvidence.lifetime = .keepAlways; add(sceneEvidence)
        let scene = try XCTUnwrap(activeScene, "A hosted math fixture requires an active application UIWindowScene.")
        let oldKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        defer {
            window.isHidden = true
            window.rootViewController = nil
            oldKeyWindow?.makeKeyAndVisible()
        }
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        XCTAssertTrue(window.windowScene === scene)
        XCTAssertTrue(controller.view.window === window)
        XCTAssertTrue(window.isKeyWindow)
        let deadline = ContinuousClock.now + .seconds(10)
        var mathView: WKWebView?
        var timeline: [String] = []
        var observed: [ObjectIdentifier: MathNavigationDiagnostics] = [:]
        var previousState = ""
        while ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            let views = descendants(controller.view).compactMap { $0 as? WKWebView }
            for view in views where observed[ObjectIdentifier(view)] == nil {
                let observer = MathNavigationDiagnostics(forwarding: view.navigationDelegate)
                observed[ObjectIdentifier(view)] = observer
                view.navigationDelegate = observer
            }
            let state = views.map { view in
                "web=\(ObjectIdentifier(view)) url=\(view.url?.absoluteString ?? "nil") loading=\(view.isLoading) progress=\(view.estimatedProgress) frame=\(view.convert(view.bounds, to: window)) attached=\(view.window === window)"
            }.joined(separator: "\n")
            if state != previousState || timeline.isEmpty {
                timeline.append("remaining=\(ContinuousClock.now.duration(to: deadline)) visibleWebViews=\(views.count)\n" + state)
                previousState = state
            }
            mathView = views.first
            if let mathView, mathView.url?.absoluteString == "about:blank", !mathView.isLoading,
               mathView.scrollView.contentSize.height > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        // Preserve diagnostics BEFORE unwrap can throw. A transient WKWebView
        // that later becomes renderer fallback must not erase all useful evidence.
        let events = observed.values.flatMap(\.events).joined(separator: "\n")
        let diagnostic = XCTAttachment(string: "Failure condition: actual WKWebView must remain mounted and load about:blank.\n"
            + sceneDescription() + "\n" + timeline.joined(separator: "\n")
            + "\nNavigation events and errors:\n" + events + "\nNative/accessible hierarchy:\n" + hierarchyDescription(window))
        diagnostic.name = "Native MessageRow math lifecycle and hierarchy - \(dark ? "dark accessibility" : "light")"
        diagnostic.lifetime = .keepAlways; add(diagnostic)
        capture(window: window, name: "Native MessageRow fixture BEFORE math assertions - \(dark ? "dark accessibility" : "light") - NOT inference")
        let web = try XCTUnwrap(mathView, "The actual MessageRow must retain the rich math WKWebView. See captured lifecycle, navigation errors and screenshot.")
        XCTAssertEqual(web.url?.absoluteString, "about:blank")
        XCTAssertFalse(web.isLoading)
        XCTAssertFalse(web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(web.configuration.websiteDataStore.isPersistent)
        XCTAssertGreaterThan(web.bounds.width, 0)
        XCTAssertLessThanOrEqual(web.bounds.width, 350)
        XCTAssertGreaterThanOrEqual(web.bounds.height, 44)
        XCTAssertLessThanOrEqual(web.bounds.height, 500)
        capture(window: window, name: "Native MessageRow fixture - \(dark ? "dark accessibility" : "light") - NOT model inference")
    }

    private func capture(window: UIWindow, name: String) {
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let capture = XCTAttachment(image: image)
        capture.name = name + (drawn ? "" : " - hierarchy drawing returned false")
        capture.lifetime = .keepAlways; add(capture)
    }

    private func sceneDescription() -> String {
        UIApplication.shared.connectedScenes.map { scene in
            let windows = (scene as? UIWindowScene)?.windows.map {
                "window frame=\($0.frame) hidden=\($0.isHidden) key=\($0.isKeyWindow) root=\(String(describing: $0.rootViewController))"
            }.joined(separator: "\n") ?? "no windows"
            return "scene=\(scene.session.persistentIdentifier) activation=\(scene.activationState.rawValue)\n" + windows
        }.sorted().joined(separator: "\n")
    }

    private func hierarchyDescription(_ root: UIView) -> String {
        var seen = Set<ObjectIdentifier>()
        var lines: [String] = []
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 30, lines.count < 800, seen.insert(ObjectIdentifier(object)).inserted else { return }
            let frame = (object as? UIView).map { " frame=\($0.frame) hidden=\($0.isHidden)" } ?? ""
            lines.append(String(repeating: " ", count: depth) + String(describing: type(of: object)) + frame
                + " label=\(object.accessibilityLabel ?? "nil") value=\(object.accessibilityValue ?? "nil")")
            if let view = object as? UIView { for child in view.subviews { visit(child, depth: depth + 1) } }
            if let children = object.accessibilityElements {
                for case let child as NSObject in children { visit(child, depth: depth + 1) }
            } else {
                let count = object.accessibilityElementCount()
                if count > 0 && count < 200 {
                    for index in 0..<count {
                        if let child = object.accessibilityElement(at: index) as? NSObject { visit(child, depth: depth + 1) }
                    }
                }
            }
        }
        visit(root, depth: 0)
        return lines.joined(separator: "\n")
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
}


/// Test-only transparent forwarding observer. Policy decisions and production
/// failure callbacks are retained; diagnostics never relax renderer restrictions.
@MainActor
private final class MathNavigationDiagnostics: NSObject, WKNavigationDelegate {
    private let original: (any WKNavigationDelegate)?
    private(set) var events: [String] = []
    init(forwarding original: (any WKNavigationDelegate)?) { self.original = original }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        events.append("navigation request: \(navigationAction.request.url?.absoluteString ?? "nil"), type \(navigationAction.navigationType.rawValue)")
        let forwarded: Void? = original?.webView?(webView, decidePolicyFor: navigationAction, decisionHandler: { [weak self] policy in
            self?.events.append("production navigation policy: \(policy.rawValue)")
            decisionHandler(policy)
        })
        // Never let diagnostics turn a missing production policy into a bypass.
        if forwarded == nil { events.append("Missing production policy delegate; fail closed"); decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        events.append("finished: \(webView.url?.absoluteString ?? "nil")")
        original?.webView?(webView, didFinish: navigation)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        events.append("navigation failure: \(error as NSError)")
        original?.webView?(webView, didFail: navigation, withError: error)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        events.append("provisional failure: \(error as NSError)")
        original?.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        events.append("web content process terminated")
        original?.webViewWebContentProcessDidTerminate?(webView)
    }
}
