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
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        let deadline = ContinuousClock.now + .seconds(10)
        var mathView: WKWebView?
        while ContinuousClock.now < deadline {
            controller.view.layoutIfNeeded()
            mathView = descendants(controller.view).compactMap { $0 as? WKWebView }.first
            if let mathView, mathView.url?.absoluteString == "about:blank", !mathView.isLoading,
               mathView.scrollView.contentSize.height > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let web = try XCTUnwrap(mathView, "The actual MessageRow must use the rich renderer, not the old plain Markdown renderer.")
        XCTAssertEqual(web.url?.absoluteString, "about:blank")
        XCTAssertFalse(web.isLoading)
        XCTAssertFalse(web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(web.configuration.websiteDataStore.isPersistent)
        XCTAssertGreaterThan(web.bounds.width, 0)
        XCTAssertLessThanOrEqual(web.bounds.width, 350)
        XCTAssertGreaterThanOrEqual(web.bounds.height, 44)
        XCTAssertLessThanOrEqual(web.bounds.height, 500)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let capture = XCTAttachment(image: image)
        capture.name = "Native MessageRow fixture - \(dark ? "dark accessibility" : "light") - NOT model inference"
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
