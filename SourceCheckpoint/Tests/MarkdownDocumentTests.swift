import XCTest
@testable import JarvisEVO

/// Exact production parser and lexical highlighter; not native rendering validation.
final class MarkdownDocumentTests: XCTestCase {
    func testHeadingsRequireWhitespaceAndPreserveUnicode() {
        XCTAssertEqual(kinds("# Café 🦉\n\n## 日本語 ##\n\n#hashtag"), [
            .heading(level: 1, text: "Café 🦉"),
            .heading(level: 2, text: "日本語"), .paragraph("#hashtag")
        ])
    }

    func testSetextHeadingsAndThematicBreakAreDistinct() {
        XCTAssertEqual(kinds("Heading\n===\n\n---\n\nText\n---"), [
            .heading(level: 1, text: "Heading"), .thematicBreak,
            .heading(level: 2, text: "Text")
        ])
    }

    func testParagraphSoftBreaksAndCRLFAreRetained() {
        XCTAssertEqual(kinds("First\r\nsecond\r\n\r\nthird"), [.paragraph("First\nsecond"), .paragraph("third")])
    }

    func testUnclosedFenceRetainsStreamingTextAndDoesNotParseMarkdown() throws {
        let code = try XCTUnwrap(codeBlocks("```swift\n# not a heading\nlet 🦉 = \"café\"").first)
        XCTAssertEqual(code.language, "swift")
        XCTAssertEqual(code.text, "# not a heading\nlet 🦉 = \"café\"")
        XCTAssertFalse(code.isClosed)
    }

    func testFenceMustMatchCharacterLengthAndHaveNoTrailingContent() throws {
        let source = "````swift\n```\n~~~\n```` not a close\n````\nAfter"
        let code = try XCTUnwrap(codeBlocks(source).first)
        XCTAssertEqual(code.text, "```\n~~~\n```` not a close\n")
        XCTAssertTrue(code.isClosed)
        XCTAssertEqual(kinds(source).last, .paragraph("After"))
    }

    func testTildeFenceEmptyFenceAndOpeningIndent() throws {
        XCTAssertEqual(codeBlocks("~~~text\n~~~").first?.text, "")
        XCTAssertEqual(codeBlocks("  ~~~json\n  {\"a\": 1}\n  ~~~").first?.text, "{\"a\": 1}\n")
    }

    func testStreamingPrefixesNeverLoseUnicodeOrCrash() {
        let source = "```swift\nlet café = \"🦉日本語\"\n```"
        for end in source.indices {
            let prefix = String(source[..<end])
            let document = MarkdownDocument(source: prefix)
            if prefix.hasPrefix("```swift\n"), !prefix.hasSuffix("\n```") {
                XCTAssertEqual(document.blocks.first?.kind, .code(.init(language: "swift", text: String(prefix.dropFirst(9)), isClosed: false)))
            }
        }
    }

    func testTablesRespectEscapedPipesCodePipesAndAlignment() throws {
        let table = try XCTUnwrap(tables("| Name | Value |\n| :--- | ---: |\n| a\\|b | `x|y` |\n| 🦉 | 42 |").first)
        XCTAssertEqual(table.headers, ["Name", "Value"])
        XCTAssertEqual(table.alignments, [.leading, .trailing])
        XCTAssertEqual(table.rows, [["a|b", "`x|y`"], ["🦉", "42"]])
    }

    func testShortTableRowsArePaddedButExtraCellsAreNeverDiscarded() throws {
        let table = try XCTUnwrap(tables("A | B\n--- | ---\nonly |\n1 | 2 | 3").first)
        XCTAssertEqual(table.rows, [["only", ""]])
        XCTAssertEqual(kinds("A | B\n--- | ---\nonly |\n1 | 2 | 3").last, .paragraph("1 | 2 | 3"))
    }

    func testInvalidTableDelimiterRemainsReadableParagraph() {
        XCTAssertEqual(kinds("A | B\n-- | ---\nx | y"), [.paragraph("A | B\n-- | ---\nx | y")])
    }

    func testUnmatchedCodeTickDoesNotSwallowTableColumns() throws {
        let table = try XCTUnwrap(tables("A | B\n--- | ---\n`open | rest").first)
        XCTAssertEqual(table.rows, [["`open", "rest"]])
    }

    func testOrderedListKeepsStartAndNestedList() throws {
        guard case .list(let ordered, let items) = try XCTUnwrap(kinds("3. Third\n   - Child\n4. Fourth").first) else {
            return XCTFail("Expected an ordered list")
        }
        XCTAssertTrue(ordered)
        XCTAssertEqual(items.map(\.number), [3, 4])
        XCTAssertEqual(items[0].blocks.first?.kind, .paragraph("Third"))
        guard case .list(let nestedOrdered, let nestedItems) = items[0].blocks.last?.kind else { return XCTFail("Expected nested list") }
        XCTAssertFalse(nestedOrdered)
        XCTAssertEqual(nestedItems.first?.blocks.first?.kind, .paragraph("Child"))
    }

    func testTaskListStateIsContentNotAnInteractiveControl() throws {
        guard case .list(_, let items) = try XCTUnwrap(kinds("- [x] Done\n- [ ] Pending\n- Ordinary").first) else { return XCTFail("Expected list") }
        XCTAssertEqual(items.map(\.isChecked), [true, false, nil])
        XCTAssertEqual(items[0].blocks.first?.kind, .paragraph("Done"))
    }

    func testQuoteRecursivelyContainsHeadingAndCode() throws {
        guard case .quote(let blocks) = try XCTUnwrap(kinds("> # Quoted\n>\n> ```text\n> <script>alert(1)</script>\n> ```").first) else { return XCTFail("Expected quote") }
        XCTAssertEqual(blocks.first?.kind, .heading(level: 1, text: "Quoted"))
        XCTAssertEqual(blocks.last?.kind, .code(.init(language: "text", text: "<script>alert(1)</script>\n", isClosed: true)))
    }

    func testRawHTMLIsContentAndCannotBecomeAnExecutableBlock() {
        XCTAssertEqual(kinds("<script>alert(1)</script>\n<img src='https://tracker.invalid/pixel'>"), [
            .paragraph("<script>alert(1)</script>\n<img src='https://tracker.invalid/pixel'>")
        ])
    }

    func testDisplayMathDelimitersAndStreamingState() {
        XCTAssertEqual(kinds("$$x^2 + y^2$$"), [.math(.init(source: "x^2 + y^2", isClosed: true))])
        XCTAssertEqual(kinds("\\[\n\\frac{1}{2}\n\\]"), [.math(.init(source: "\\frac{1}{2}", isClosed: true))])
        XCTAssertEqual(kinds("$$\n\\frac{1}"), [.math(.init(source: "\\frac{1}", isClosed: false))])
        XCTAssertEqual(kinds("Price is $5 and inline $x$ stays text."), [.paragraph("Price is $5 and inline $x$ stays text.")])
    }

    func testDeepNestingIsBoundedAndFallbackPreservesContent() {
        let source = String(repeating: "> ", count: 100) + "retained"
        XCTAssertEqual(kinds(source), [.plainSource(source: source, reason: .nesting)])
    }

    func testLinkPolicyRejectsExecutableLocalAndCredentialURLs() {
        for value in ["javascript:alert(1)", "data:text/html,<script>", "file:///private/a", "jarvis://delete", "https://user:pass@example.com/", "//example.com", "https://example.com/\nsecret", "https://example.com/%0Asecret"] {
            XCTAssertNil(MarkdownLinkPolicy.allowedURL(value), value)
        }
        XCTAssertEqual(MarkdownLinkPolicy.allowedURL("https://example.com/path?q=1")?.host, "example.com")
        XCTAssertNotNil(MarkdownLinkPolicy.allowedURL("http://example.com"))
    }

    func testHighlighterKeepsEveryCharacterAndDoesNotHighlightInsideStringsOrComments() {
        let source = "let café = \"return 42 🦉\" // let 7\nreturn 23"
        let tokens = MarkdownSyntaxHighlighter.tokens(source, language: "swift")
        XCTAssertEqual(tokens.map(\.text).joined(), source)
        XCTAssertTrue(tokens.contains(.init(text: "let", style: .keyword)))
        XCTAssertTrue(tokens.contains(.init(text: "\"return 42 🦉\"", style: .string)))
        XCTAssertTrue(tokens.contains(.init(text: "// let 7", style: .comment)))
        XCTAssertTrue(tokens.contains(.init(text: "23", style: .number)))
    }

    func testHighlighterDoesNotClaimUnknownLanguagesAndBoundsWork() {
        XCTAssertEqual(MarkdownSyntaxHighlighter.tokens("hello 123", language: "unknown"), [.init(text: "hello 123", style: .plain)])
        let large = String(repeating: "let x = 1\n", count: 20_000)
        XCTAssertEqual(MarkdownSyntaxHighlighter.tokens(large, language: "swift"), [.init(text: large, style: .plain)])
    }

    func testHighlighterTreatsUnterminatedStringAsStreamingString() {
        XCTAssertEqual(MarkdownSyntaxHighlighter.tokens("\"hello 🦉", language: "json"), [.init(text: "\"hello 🦉", style: .string)])
        let source = "/* never closed\nlet x = 1"
        XCTAssertEqual(MarkdownSyntaxHighlighter.tokens(source, language: "swift"), [.init(text: source, style: .comment)])
    }

    func testOversizedMarkdownUsesVisibleLiteralFallback() {
        let source = String(repeating: "# retained\n", count: 50_000)
        XCTAssertEqual(kinds(source), [.plainSource(source: source, reason: .sourceBytes)])
    }

    // These fixtures are below the byte limit: byte bounds alone cannot prevent view explosion.
    func testManyTableRowsFallBackWithoutDroppingTailOrChangingOriginalNewlines() {
        let source = "A | B\r\n--- | ---\r\n" + String(repeating: "x | y\r\n", count: 10_000) + "🦉 final row"
        XCTAssertLessThan(source.utf8.count, 500_000)
        XCTAssertEqual(kinds(source), [.plainSource(source: source, reason: .tableRows)])
    }

    func testWideTableFallsBackInsteadOfAllocatingUnboundedCells() {
        let header = Array(repeating: "h", count: 5_000).joined(separator: " | ")
        let delimiter = Array(repeating: "---", count: 5_000).joined(separator: " | ")
        let source = header + "\n" + delimiter + "\nretained"
        XCTAssertLessThan(source.utf8.count, 500_000)
        XCTAssertEqual(kinds(source), [.plainSource(source: source, reason: .tableColumns)])
    }

    func testTotalCellBudgetIncludesHeadersAndAllTables() {
        let header = Array(repeating: "h", count: 32).joined(separator: " | ")
        let delimiter = Array(repeating: "---", count: 32).joined(separator: " | ")
        let accepted = header + "\n" + delimiter + "\n" + String(repeating: header + "\n", count: 63)
        XCTAssertEqual(tables(accepted).first?.rows.count, 63, "2,048 cells including the header remain supported")
        let rejected = accepted + header
        XCTAssertEqual(kinds(rejected), [.plainSource(source: rejected, reason: .tableCells)])
    }

    func testTotalRowBudgetAppliesAcrossSmallTables() {
        let table = "A | B\n--- | ---\n" + String(repeating: "x | y\n", count: 100)
        let source = [table, table, table].joined(separator: "\n")
        XCTAssertEqual(kinds(source), [.plainSource(source: source, reason: .totalTableRows)])
    }

    func testManyTinyBlocksFallBackBeforeCreatingThousandsOfViews() {
        let source = String(repeating: "# H\n", count: 10_000)
        XCTAssertEqual(kinds(source), [.plainSource(source: source, reason: .blocks)])
        XCTAssertEqual(MarkdownDocument(source: String(repeating: "# H\n", count: 256)).blocks.count, 256)
    }

    func testEmptyListItemsStillConsumeTheSharedItemBudget() {
        let source = String(repeating: "-\n", count: 10_000)
        XCTAssertEqual(kinds(source), [.plainSource(source: source, reason: .listItems)])
    }

    func testNestedBranchesShareOneBlockBudget() {
        let child = String(repeating: "> # Child\n", count: 128)
        let source = child + "\n" + child
        XCTAssertEqual(kinds(source), [.plainSource(source: source, reason: .blocks)])
    }

    func testMathViewBudgetAvoidsOneWebViewPerTinyExpression() {
        let source = String(repeating: "$$x$$\n", count: 17)
        XCTAssertEqual(kinds(source), [.plainSource(source: source, reason: .mathBlocks)])
        XCTAssertEqual(MarkdownDocument(source: String(repeating: "$$x$$\n", count: 16)).blocks.count, 16)
    }

    func testLineBudgetCatchesManyBlankLinesAndKeepsExactOriginalSource() {
        let source = "start\r\n" + String(repeating: "\r\n", count: 20_000) + "end"
        XCTAssertEqual(kinds(source), [.plainSource(source: source, reason: .sourceLines)])
    }

    func testOrdinaryTableStillRendersAtRowBudgetBoundary() throws {
        let source = "Name | Value\n:--- | ---:\n" + String(repeating: "Café 🦉 | 42\n", count: 128)
        let table = try XCTUnwrap(tables(source).first)
        XCTAssertEqual(table.headers, ["Name", "Value"])
        XCTAssertEqual(table.rows.count, 128)
        XCTAssertEqual(table.rows.last, ["Café 🦉", "42"])
        XCTAssertEqual(table.alignments, [.leading, .trailing])
    }

    func testRepresentativeLargeAndAdversarialParsingHasCoarseTimeBudget() {
        let longLine = "Café 日本語 🦉 " + String(repeating: "text ", count: 20) + "\n"
        let paragraph = String(repeating: longLine, count: 2_000)
        let manyRows = "A | B\n--- | ---\n" + String(repeating: "x | y\n", count: 10_000)
        let manyBlocks = String(repeating: "# H\n", count: 10_000)
        let start = Date()
        for source in [paragraph, manyRows, manyBlocks] {
            XCTAssertFalse(MarkdownDocument(source: source).blocks.isEmpty)
        }
        // A broad regression gate for the test host, not an iPhone rendering benchmark.
        XCTAssertLessThan(Date().timeIntervalSince(start), 5.0)
    }

    private func kinds(_ source: String) -> [MarkdownBlock.Kind] { MarkdownDocument(source: source).blocks.map(\.kind) }
    private func codeBlocks(_ source: String) -> [MarkdownCodeBlock] { kinds(source).compactMap { if case .code(let code) = $0 { return code }; return nil } }
    private func tables(_ source: String) -> [MarkdownTable] { kinds(source).compactMap { if case .table(let table) = $0 { return table }; return nil } }
}
