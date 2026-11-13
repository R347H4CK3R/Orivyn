import XCTest
import SwiftUI
import UIKit
@testable import JarvisEVO

/// Native resource/layout cases. Native execution is required.
final class RichMessageContentTests: XCTestCase {
    @MainActor
    func testFallbackUsesOneBoundedSelectableNoninteractiveTextView() {
        let source = String(repeating: "# retained 🦉\n", count: 1_000)
        let controller = UIHostingController(rootView: RichMessageContent(text: source))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let textViews = descendants(controller.view).compactMap { $0 as? UITextView }
        XCTAssertEqual(textViews.count, 1)
        guard let textView = textViews.first else { return }
        XCTAssertEqual(textView.text, source)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isScrollEnabled)
        XCTAssertEqual(textView.dataDetectorTypes, [])
        XCTAssertLessThanOrEqual(textView.frame.height, 320)
        XCTAssertGreaterThan(textView.frame.height, 0)
    }

    func testNativeInlineContentKeepsRawHTMLVisibleAndStripsUnsafeLinkActions() {
        let value = RichInlineMarkdown.attributed("<script>alert(1)</script> [bad](javascript:alert) [safe](https://example.com)")
        XCTAssertTrue(String(value.characters).contains("<script>alert(1)</script>"))
        XCTAssertEqual(value.runs.compactMap(\.link).map(\.absoluteString), ["https://example.com"])
    }

    func testPinnedMathRendererRendersRealFractionAndMatrix() async {
        for source in [#"\frac{1}{2}"#, #"\begin{pmatrix}a & b \\ c & d\end{pmatrix}"#] {
            let result = await OfflineMathRenderer.shared.render(source)
            guard case .rendered(let html) = result else { return XCTFail("Actual bundled KaTeX failed: \(result)") }
            XCTAssertTrue(html.contains("<math"))
            XCTAssertTrue(html.contains("<mfrac>") || html.contains("<mtable"))
            XCTAssertFalse(html.contains("<script"))
        }
    }

    func testMathRendererRejectsMalformedAndOversizedExpressions() async {
        let malformed = await OfflineMathRenderer.shared.render(#"\frac{"#)
        guard case .fallback = malformed else { return XCTFail("Malformed input must remain visible as source") }
        let oversized = await OfflineMathRenderer.shared.render(String(repeating: "x", count: 8_193))
        guard case .fallback = oversized else { return XCTFail("Bounded input must use source fallback") }
    }

    func testMathRendererDoesNotExecuteOrLoadModelHTMLURLsOrMacros() async {
        for source in [#"\href{javascript:alert(1)}{click}"#, #"\includegraphics{https://tracker.invalid/pixel}"#, #"\htmlClass{bad}{x}"#, #"\text{<script>alert(1)</script>}"#, #"\def\x{\x}\x"#] {
            let result = await OfflineMathRenderer.shared.render(source)
            if case .rendered(let html) = result {
                XCTAssertFalse(html.contains("<script"), source)
                XCTAssertFalse(html.contains("<img"), source)
                XCTAssertFalse(html.contains("href="), source)
                XCTAssertFalse(html.contains("src="), source)
                XCTAssertFalse(html.contains("class=\"bad\""), source)
            }
        }
        let definition = await OfflineMathRenderer.shared.render(#"\gdef\privateMacro{1}\privateMacro"#)
        guard case .rendered = definition else { return XCTFail("Macro fixture should render locally") }
        let next = await OfflineMathRenderer.shared.render(#"\privateMacro"#)
        guard case .fallback = next else { return XCTFail("Macros must not escape their expression") }
    }

}
