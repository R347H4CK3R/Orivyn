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

    func testMathInkGateRejectsBlankWrongAppearanceAndRuleOnlySurfaces() throws {
        // Negative measurement fixtures only, never used as app or WK evidence.
        for dark in [false, true] {
            for fill in [UIColor.white, UIColor.black, UIColor.clear] {
                let blank = UIGraphicsImageRenderer(size: CGSize(width: 350, height: 179)).image { context in
                    context.cgContext.setFillColor(fill.cgColor)
                    context.cgContext.fill(CGRect(x: 0, y: 0, width: 350, height: 179))
                }
                XCTAssertFalse(try fractionInk(in: blank, dark: dark).hasFractionStructure)
            }
            let rule = UIGraphicsImageRenderer(size: CGSize(width: 350, height: 179)).image { context in
                context.cgContext.setFillColor((dark ? UIColor.black : UIColor.white).cgColor)
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 350, height: 179))
                context.cgContext.setFillColor((dark ? UIColor.white : UIColor.black).cgColor)
                context.cgContext.fill(CGRect(x: 165, y: 80, width: 20, height: 1))
            }
            XCTAssertFalse(try fractionInk(in: rule, dark: dark).hasFractionStructure)
        }
    }

    func testMathInkGateRejectsConnectedRectangleAndPlusSign() throws {
        // Counterexamples to the old row-count predicate. These are negative
        // measurement inputs only, never replacement math or rendering evidence.
        for dark in [false, true] {
            for scale in [CGFloat(1), 2, 3] {
                for plus in [false, true] {
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = scale
                    let image = UIGraphicsImageRenderer(size: CGSize(width: 350, height: 179), format: format).image { context in
                        context.cgContext.setFillColor((dark ? UIColor.black : UIColor.white).cgColor)
                        context.cgContext.fill(CGRect(x: 0, y: 0, width: 350, height: 179))
                        context.cgContext.setFillColor((dark ? UIColor.white : UIColor.black).cgColor)
                        if plus {
                            context.cgContext.fill(CGRect(x: 165, y: 85, width: 20, height: 2))
                            context.cgContext.fill(CGRect(x: 174, y: 76, width: 2, height: 20))
                        } else {
                            context.cgContext.fill(CGRect(x: 165, y: 80, width: 20, height: 10))
                        }
                    }
                    XCTAssertFalse(try fractionInk(in: image, dark: dark).hasFractionStructure,
                        "A connected \(plus ? "plus sign" : "rectangle") at \(scale)x in \(dark ? "dark" : "light") is not a fraction.")
                }
            }
        }
    }

    func testMathInkGateAcceptsSeparatedMeasurementControl() throws {
        // This proves the measurement predicate is not always false. It does
        // NOT establish WebKit rendering: only the actual WK snapshots do that.
        for dark in [false, true] {
            for scale in [CGFloat(1), 2, 3] {
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                let image = UIGraphicsImageRenderer(size: CGSize(width: 350, height: 179), format: format).image { context in
                    let foreground: UIColor = dark ? .white : .black
                    context.cgContext.setFillColor((dark ? UIColor.black : UIColor.white).cgColor)
                    context.cgContext.fill(CGRect(x: 0, y: 0, width: 350, height: 179))
                    let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .regular), .foregroundColor: foreground]
                    for (text, y) in [("1", CGFloat(54)), ("2", CGFloat(94))] {
                        let string = NSAttributedString(string: text, attributes: attributes)
                        string.draw(at: CGPoint(x: 175 - string.size().width / 2, y: y))
                    }
                    context.cgContext.setFillColor(foreground.cgColor)
                    context.cgContext.fill(CGRect(x: 165, y: 85, width: 20, height: 2))
                }
                XCTAssertTrue(try fractionInk(in: image, dark: dark).hasFractionStructure,
                    "Separated measurement glyphs and bar at \(scale)x must be recognized independently of WebKit.")
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
        // Hosted cold WebKit/GPU process launch was measured at 22.55 seconds.
        // Retain all loaded-page, security, geometry and pixel assertions.
        let deadline = ContinuousClock.now + .seconds(30)
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
        try await verifyActualMathSnapshot(web, window: window, dark: dark)
        capture(window: window, name: "Native MessageRow fixture - \(dark ? "dark accessibility" : "light") - NOT model inference")
    }

    /// drawHierarchy omits remote WebKit pixels. Capture the actual compositor
    /// surface without executing JavaScript or replacing the production markup.
    private func verifyActualMathSnapshot(_ web: WKWebView, window: UIWindow, dark: Bool) async throws {
        // The large-text fixture's math extended below the visible viewport in
        // run9. Scroll the enclosing native transcript, not the math document.
        var ancestor = web.superview
        var hostScroll: UIScrollView?
        while let view = ancestor {
            if let scroll = view as? UIScrollView { hostScroll = scroll; break }
            ancestor = view.superview
        }
        let scroll = try XCTUnwrap(hostScroll, "Math must be inside the actual hosted message scroll view.")
        let readyDeadline = ContinuousClock.now + .seconds(5)
        var previousFrame = CGRect.null
        var stableSamples = 0
        var visible = false
        repeat {
            scroll.scrollRectToVisible(web.convert(web.bounds, to: scroll).insetBy(dx: 0, dy: -8), animated: false)
            window.layoutIfNeeded()
            let frame = web.convert(web.bounds, to: window)
            let visibleFrame = frame.intersection(window.bounds).intersection(scroll.convert(scroll.bounds, to: window))
            visible = !visibleFrame.isNull && visibleFrame.width >= frame.width - 1 && visibleFrame.height >= frame.height - 1
            if visible, !web.isLoading, web.estimatedProgress == 1, frame == previousFrame { stableSamples += 1 }
            else { stableSamples = 0 }
            previousFrame = frame
            if stableSamples >= 2 { break }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < readyDeadline
        let viewport = XCTAttachment(string: "Math frame on window=\(previousFrame); window=\(window.bounds); host viewport=\(scroll.convert(scroll.bounds, to: window)); fully visible=\(visible); stable ready samples=\(stableSamples); appearance=\(web.traitCollection.userInterfaceStyle.rawValue)")
        viewport.name = "Actual math snapshot viewport - \(dark ? "dark" : "light")"
        viewport.lifetime = .keepAlways; add(viewport)
        capture(window: window, name: "Actual MessageRow after bringing math onscreen - \(dark ? "dark" : "light") - remote pixels captured separately")
        XCTAssertTrue(visible, "The complete math surface must be onscreen before capture.")
        XCTAssertGreaterThanOrEqual(stableSamples, 2)
        XCTAssertEqual(web.traitCollection.userInterfaceStyle, dark ? .dark : .light)
        let configuration = WKSnapshotConfiguration()
        configuration.rect = web.bounds
        configuration.afterScreenUpdates = true
        let snapshot: UIImage
        do { snapshot = try await web.takeSnapshot(configuration: configuration) }
        catch {
            let failure = XCTAttachment(string: "Actual WKWebView.takeSnapshot failed: \(error as NSError)\n" + hierarchyDescription(window))
            failure.name = "Math compositor snapshot failure"; failure.lifetime = .keepAlways; add(failure)
            throw error
        }
        let attachment = XCTAttachment(image: snapshot)
        attachment.name = "ACTUAL WKWebView fraction pixels - \(dark ? "dark accessibility" : "light") - controlled fixture, not inference"
        attachment.lifetime = .keepAlways; add(attachment)
        let ink = try fractionInk(in: snapshot, dark: dark)
        let measurements = XCTAttachment(string: ink.description)
        measurements.name = "Actual math fraction ink measurements - \(dark ? "dark" : "light")"
        measurements.lifetime = .keepAlways; add(measurements)
        XCTAssertGreaterThan(ink.foregroundPixels, 20, "A loaded but blank WebKit document does not prove visible math.")
        XCTAssertLessThan(ink.foregroundFraction, 0.15, "A uniformly opaque wrong-color surface is not math ink.")
        XCTAssertTrue(ink.hasFractionStructure, "The controlled fraction must have visible numerator/denominator ink separated by a horizontal fraction bar.")
    }

    private struct FractionInk {
        let foregroundPixels: Int
        let foregroundFraction: Double
        let hasFractionStructure: Bool
        let description: String
    }

    /// Analyze original snapshot pixels over the known appearance background.
    /// Ignore edge scroll indicators. The known 1/2 fixture must have three
    /// distinct occupied row bands: numerator, horizontal rule, denominator.
    /// Actual blank scanlines, not skipped neighbors, must separate each band.
    private func fractionInk(in image: UIImage, dark: Bool) throws -> FractionInk {
        let bitmap = try XCTUnwrap(image.cgImage)
        let width = bitmap.width, height = bitmap.height
        XCTAssertGreaterThan(width, 0); XCTAssertGreaterThan(height, 0)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor((dark ? UIColor.black : UIColor.white).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let sx = CGFloat(width) / max(1, image.size.width)
        let sy = CGFloat(height) / max(1, image.size.height)
        let insetX = max(1, Int(8 * sx)), insetY = max(1, Int(2 * sy))
        guard width > insetX * 2, height > insetY * 2 else {
            return FractionInk(foregroundPixels: 0, foregroundFraction: 0, hasFractionStructure: false, description: "Snapshot is too small to contain a visible fraction: \(width)x\(height)")
        }
        var rows = [Int](repeating: 0, count: height)
        var longestRuns = rows
        var rowMinX = [Int](repeating: width, count: height)
        var rowMaxX = [Int](repeating: -1, count: height)
        var count = 0, minX = width, maxX = -1, minY = height, maxY = -1
        for y in insetY..<(height - insetY) {
            var run = 0
            for x in insetX..<(width - insetX) {
                let i = (y * width + x) * 4
                let luminance = (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
                let foreground = dark ? luminance > 160 : luminance < 95
                if foreground {
                    count += 1; rows[y] += 1; run += 1
                    longestRuns[y] = max(longestRuns[y], run)
                    rowMinX[y] = min(rowMinX[y], x); rowMaxX[y] = max(rowMaxX[y], x)
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                } else { run = 0 }
            }
        }
        // Maximal occupied bands are separated by >=1 completely blank pixel
        // row across the interior. A solid rectangle or connected plus forms
        // one band, so cannot supply its own numerator/bar/denominator.
        var bands: [Range<Int>] = []
        var bandStart: Int?
        for y in insetY..<(height - insetY) {
            if rows[y] > 0 {
                if bandStart == nil { bandStart = y }
            } else if let start = bandStart {
                bands.append(start..<y); bandStart = nil
            }
        }
        if let start = bandStart { bands.append(start..<(height - insetY)) }
        var separatedFraction = false
        if bands.count == 3, minX <= maxX {
            let numerator = bands[0], bar = bands[1], denominator = bands[2]
            let barLeft = rowMinX[bar].min() ?? width
            let barRight = rowMaxX[bar].max() ?? -1
            let barWidth = barRight - barLeft + 1
            let horizontalTolerance = max(1, Int(ceil(sx)))
            let requiredRun = max(3, Int(ceil(Double(maxX - minX + 1) * 0.60)))
            func isGlyphBand(_ band: Range<Int>) -> Bool {
                // Distinct, vertically extended ink contained over/under the
                // bar. This uses relative geometry, not a font or digit bitmap.
                rows[band].reduce(0, +) >= 3 && band.count > bar.count
                    && (rowMinX[band].min() ?? width) >= barLeft - horizontalTolerance
                    && (rowMaxX[band].max() ?? -1) <= barRight + horizontalTolerance
            }
            separatedFraction = barWidth >= 3 * bar.count
                && (longestRuns[bar].max() ?? 0) >= requiredRun
                && isGlyphBand(numerator) && isGlyphBand(denominator)
        }
        let fraction = Double(count) / Double((width - insetX * 2) * (height - insetY * 2))
        let bandDescription = bands.map { band in
            "rows=\(band), pixels=\(rows[band].reduce(0, +)), x=\(rowMinX[band].min() ?? width)...\(rowMaxX[band].max() ?? -1), longest run=\(longestRuns[band].max() ?? 0)"
        }.joined(separator: "; ")
        return FractionInk(foregroundPixels: count, foregroundFraction: fraction, hasFractionStructure: fraction < 0.15 && separatedFraction,
            description: "Original snapshot=\(width)x\(height) pixels / \(image.size) points, appearance=\(dark ? "dark" : "light"), foreground pixels=\(count), foreground fraction=\(fraction), ink bounds=(\(minX),\(minY))..(\(maxX),\(maxY)), occupied bands=[\(bandDescription)]. Thresholds: lightRGB<95/darkRGB>160; exactly three bands separated by fully blank scanlines; middle bar width≥3×height and contiguous run≥60% of ink width; upper/lower glyph bands taller than bar, within its horizontal extent ±1pt. Measurement never changes the supplied image or markup.")
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
