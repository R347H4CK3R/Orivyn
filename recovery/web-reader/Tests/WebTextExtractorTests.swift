import XCTest
@testable import JarvisEVO

final class WebTextExtractorTests: XCTestCase {
    func testExtractsUnicodeAndEntitiesWithoutAttributesOrExecutableMarkup() throws {
        let html = #"<!doctype html><html><head><title>A &amp; B</title><script>evil()</script></head><body><h1>Real</h1><p title="> secret">café &#x1f989; &lt;safe&gt;</p><img src="https://tracker.invalid/x"><script>if (a < b) steal()</script><style>.x{}</style><p>Last</p></body></html>"#
        let value = try WebTextExtractor.extract(Data(html.utf8), mediaType: "text/html")
        XCTAssertEqual(value.title, "A & B")
        XCTAssertEqual(value.text, "Real café 🦉 <safe> Last")
        XCTAssertFalse(value.truncated)
    }

    func testHiddenRawForeignAndTemplateContentCannotBecomeArticleText() throws {
        let html = #"<body><p>Visible</p><div hidden><p>Private</p></div><template>Hidden</template><svg><text>Hidden SVG</text></svg><iframe>Hidden frame</iframe><noscript>Fallback</noscript><p>End</p></body>"#
        XCTAssertEqual(try WebTextExtractor.extract(Data(html.utf8), mediaType: "text/html").text, "Visible End")
    }

    func testMalformedAndOvercomplexHTMLFailsInsteadOfUnboundedRecovery() {
        for html in ["<p><b>mismatch</p>", "<script>unterminated", "<!-- no close", "<p title='unterminated>text",
                     String(repeating: "<div>", count: 65) + "x" + String(repeating: "</div>", count: 65),
                     "<p " + String(repeating: "a", count: 4096) + ">x</p>"] {
            XCTAssertThrowsError(try WebTextExtractor.extract(Data(html.utf8), mediaType: "text/html"))
        }
    }

    func testByteBudgetPreservesUTF8ScalarAndMarksTruncation() throws {
        let value = try WebTextExtractor.extract(Data(String(repeating: "🦉", count: 5000).utf8), mediaType: "text/plain")
        XCTAssertEqual(value.text.utf8.count, 16384)
        XCTAssertTrue(value.truncated)
        XCTAssertEqual(value.text, String(repeating: "🦉", count: 4096))
    }

    func testPlainTextIsDataNotHTMLAndDirectionalControlsAreRemoved() throws {
        let value = try WebTextExtractor.extract(Data("<script>not executed</script>\u{202E} abc".utf8), mediaType: "text/plain")
        XCTAssertEqual(value.text, "<script>not executed</script> abc")
    }

    func testInvalidUTF8AndOversizeInputRejected() {
        XCTAssertThrowsError(try WebTextExtractor.extract(Data([0xFF]), mediaType: "text/plain"))
        XCTAssertThrowsError(try WebTextExtractor.extract(Data(repeating: 65, count: 262145), mediaType: "text/html"))
        XCTAssertThrowsError(try WebTextExtractor.extract(Data(" ".utf8), mediaType: "text/plain"))
    }
}
