# Markdown execution coverage

33 existing parser/highlighter tests moved unchanged into MarkdownDocumentTests, with their helper methods. Five native layout, inline-rendering and bundled math-renderer cases remain in RichMessageContentTests. No test assertion was removed and no production behavior changed. Both classes are explicitly retained in the manual Apple gate.

Exact copied production MarkdownDocument.swift and tests compiled and executed with official Swift 6.1.3 Linux: 187 selected XCTest cases passed, including all 33 Markdown cases. Source-manifest and full compiler/test output are in proof-14-markdown under the shared Swift validation directory. Checks cover Unicode streaming, code fences, tables, list and nesting bounds, raw HTML as text, link policy, highlighter preservation and adversarial rendering limits. The broad host parsing time check is not an iPhone benchmark.

132 Python tests pass; all 180 Swift source/test files syntax-parse. This does not type-check iOS APIs or validate actual views, WebKit, math resources or device installation. Existing Linux redirect-fixture exclusion and Observation linker blocker remain. No new IPA or catalog update.
