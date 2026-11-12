# Rich message renderer: next-candidate source

This is an **implemented but native-unverified, unintegrated** renderer. It does not replace the current `MessageRow` until a later candidate explicitly wires in `RichMessageContent(text:)` and passes native validation. No current IPA contains this work by implication.

## Supported scope

- Native SwiftUI ATX and one-line setext headings, paragraphs, thematic breaks, block quotes, ordered/unordered/nested lists, noninteractive task-list indicators, fenced code and pipe tables.
- Inline emphasis, strong text, code and links through Foundation's inline Markdown parser. Raw HTML is escaped and displayed as text. Native `Text` does not fetch image URLs.
- Tables preserve aligned columns, escaped pipes, backtick spans and Unicode. Short rows are padded; rows with extra columns revert to text rather than losing cells. Tables scroll horizontally.
- Code is selectable and its Copy button writes the exact parsed code to the clipboard, including a final newline before a closing fence. Streaming/unclosed fences stay code. The limited lexer colors strings, comments, numbers and keywords for Swift, Python, JSON/JSONC, JS/TS, shell and listed C-like languages. It is not a compiler, semantic highlighter or code executor. Unknown languages and code over 100,000 UTF-8 bytes remain selectable plain code.
- Display TeX delimited by `$$...$$` or `\[...\]` uses real local KaTeX to produce MathML, then WebKit's built-in MathML layout. Inline `$...$`/`\(...\)` expressions remain literal text. This is not complete LaTeX support; only KaTeX's supported commands, strict options and MathML output apply. Incomplete, oversized or invalid expressions remain selectable/copyable TeX. Rendered expressions retain a TeX-source disclosure and Copy TeX button.
- Model-generated links never open automatically. Only HTTP/HTTPS URLs without credentials/control characters survive sanitization. A tap shows the full destination and explicit Open, Copy and Cancel choices. Other schemes have no action.

This is a documented Markdown subset rather than a complete CommonMark/GFM parser. Reference links, footnotes, indented code, lazy quote/list continuation, multiline setext titles, inline math layout and external image rendering are outside this slice.

## Bounded native rendering and full-source fallback

Byte limits alone do not bound SwiftUI view count. Parsing therefore shares one budget across all quotes, lists and nested branches, with reservations checked **before** appending rich nodes or table cells:

- At most 500,000 UTF-8 source bytes and 20,000 normalized lines. The line limit is checked before splitting into a line array.
- At most 256 blocks in the complete document tree, not per nesting level.
- At most 256 list items across all lists, including empty items.
- At most 16 nested levels below the document root.
- At most 32 columns and 128 body rows in one table.
- At most 256 table body rows across the complete document.
- At most 2,048 table cells across the complete document, including headers and padded cells.
- At most 16 display-math blocks, limiting MathML web views as well as math tasks.

A table-row split stops after 33 cells, retaining only one over-limit sentinel column. This allows a very wide valid table to trigger the fallback without allocating thousands of cells. Backtick runs are counted in a linear pass rather than repeatedly searching suffixes.

Any exceeded budget discards the partial rich tree and emits a single explicit plain-source block. It retains the **complete original source**, including original CRLFs and the final character, without truncating or changing the stored message. The UI labels this **Plain-text view**, explains the specific limit, provides a 320-point scrolling, selectable, read-only TextKit 2 `UITextView`, and offers **Copy full source**. Markdown parsing and automatic URL/data detection are disabled in this fallback. It does not create one SwiftUI view per source line or table cell.

The eager table Grid is now bounded by these global budgets. This is a bounded rendering strategy, not a claim that any amount of text has constant memory cost: the original string still occupies memory and assigning it to a text view has a cost. Source preservation is intentional. Hardware profiling, streaming-update cost, actual TextKit viewport behavior and acceptable UI latency remain native verification gates.

Regression fixtures cover 10,000 table rows, 5,000 columns, 10,000 headings, 10,000 empty list items, shared nested budgets, CRLF/source-tail preservation, line and math-view limits, and exact row/cell boundaries. A normal two-column 128-row table remains rich; a 32-column table with 63 body rows consumes exactly 2,048 cells including its header. The native timing test gives the combined representative-large-paragraph, many-row and many-block parser fixtures a coarse five-second host budget. **That test has not run here; no timing or device-speed claim is made.**

## Pinned dependency and provenance

Only the JavaScript distribution file is bundled, unmodified. No CSS, fonts, auto-render add-on, CDN loader or npm runtime dependency is shipped. A second verbatim MIT notice is included under `JarvisEVO/Resources/KaTeX-0.19.1-LICENSE.txt` for app-bundle redistribution.

- Package/version: `katex@0.19.1`.
- Official release: <https://github.com/KaTeX/KaTeX/releases/tag/v0.19.1>, dated 2026-10-23.
- Official browser integrity listing: <https://katex.org/docs/browser.html>.
- Package metadata retrieved from <https://registry.npmjs.org/katex/0.19.1>.
- Archive source: <https://registry.npmjs.org/katex/-/katex-0.19.1.tgz>.
- Archive SHA-256: `24da5a599eb2fcede2e270b99a6ff48bca816beecc95feeb84e8cccbd1bb34fd`.
- Archive matched the registry SHA-512 integrity: `sha512-jG8uKntjSEcm2EpQOh0XturpPuuC9r3Sq5HLHdsFdWZT27E672SF19QEi+of0/YeOy15lDgRhKvr5614uRrEfA==`.
- `JarvisEVO/Resources/katex-0.19.1.min.js`: 273,081 bytes.
- JS SHA-256: `fa140498b8cfc8302cbe5e7cb1bdbc1f952bc38b3fa258ede09e73edbf9a74bc`.
- JS SHA-384 matches the official browser docs: `a1WQdjRj162i159OYq041X6I4K8NenkrI09LlPmiHg0YOb7CR+wJOraXwK9abpnE`.
- License: MIT, copyright 2013–2020 Khan Academy and other contributors. Verbatim license retained at `ThirdPartyNotices/KaTeX-0.19.1-LICENSE.txt` (1,107 bytes; SHA-256 `766ccc1f306c885aa45542a9846bbd0a505b27a0374f146778171c2254ce18e3`). Upstream: <https://github.com/KaTeX/KaTeX/blob/v0.19.1/LICENSE>.

The existing XcodeGen `JarvisEVO` source directory should discover the new JS resource and app-bundled license. Verify actual app-bundle inclusion during native build, rather than treating source discovery as proof. The renderer verifies the JS SHA-256 before execution and fails visibly to TeX source when the resource is missing or changed. No license acceptance UI, new service, payment or remote account is involved.

## Security and execution model

1. The app's actor loads only the verified bundled library into a fresh JavaScriptCore context. No browser, network API, native host object, script-message bridge or model-written JavaScript is provided. Untrusted TeX is passed as a JS function argument, never interpolated into executable source.
2. Each render uses a fresh context/macros object, `trust: false`, `strict: error`, `throwOnError: true`, MathML-only output, 8,192-byte input limit, `maxExpand: 100`, `maxSize: 10` and a 500,000-byte output limit. Parse-error strings are never inserted into HTML. Trust-rejected commands can appear as inert error text, as documented by KaTeX, rather than executing.
3. Rendering occurs on an actor away from the main UI actor. Cancellation is checked before and after the synchronous call and stale view results are ignored. There is no supported Swift JavaScriptCore hard-stop API here: a running call cannot be forcibly interrupted. Length/expansion/size limits reduce, but do not prove absence of, resource-exhaustion risk. Do not claim hard CPU-time isolation.
4. A nonpersistent WKWebView receives only trusted KaTeX-produced MathML inside a fixed app-owned template. Page JavaScript is disabled. CSP denies all resources, scripts, network connections, images, fonts, frames, forms and base changes; only the app's inline style is allowed. A deny-all WebKit content rule is installed before content loads. Failure to install it shows TeX fallback.
5. Navigation is denied except the initial `about:blank` document. Link previews are off. There are no JavaScript handlers, external fonts, CDN requests, or HTML supplied directly by a model. WebKit process failures show the source fallback.

Upstream guidance: <https://katex.org/docs/security>, <https://katex.org/docs/options>, <https://katex.org/docs/support_table>.

## Verification status

Tests were authored before their corresponding implementations. The 12 budget-regression tests were authored before the earlier workspace was lost and were restored before the budget implementation was applied. Native toolchain checks returned `xcodebuild: command not found`; this Linux executor also lacks `swift`. Therefore no native red/green cycle, compilation, parser timing, layout, clipboard, VoiceOver or JavaScriptCore/WebKit behavior is claimed. The test file contains **38 authored tests**, not 38 passing tests.

Preliminary checks available on this executor:

- Tree-sitter Swift syntax parsing, which is not Swift type checking.
- The actual pinned JS loaded and run in an isolated Node VM without browser/network globals. Fractions and matrices return MathML; malformed input and recursive macros error; HTML remains escaped; image/link commands produce no executable elements or resource-loading attributes. This is dependency smoke evidence, not a JavaScriptCore/WebKit native pass.
- Existing Python package-verifier tests, which do not validate Swift rendering.

Required next-candidate checks:

1. Build under Xcode 26 / Swift 6 strict concurrency; ensure the JS and license resources are copied. Run all 38 `RichMessageContentTests` and the full native/unit/UI suite, preserving exact commit and logs.
2. Wire the renderer into `MessageRow` only in the authorized integration cycle; add screenshots for headings, nested lists/quotes, tables, Unicode, code and display math in light/dark mode and large Dynamic Type.
3. Verify code, TeX and full-source clipboard contents, selection, horizontal/vertical scrolling, streaming fences, malformed fallback and MathML height across rotation/large formulas.
4. Verify the plain-source budget fallback actually contains one bounded selectable TextKit view, has data detectors disabled, retains complete CRLF/Unicode source and does not create the rejected rich tree. Profile adversarial and near-limit documents on iPhone hardware; a passing five-second parser-host test is not a UI-latency benchmark.
5. Inspect VoiceOver heading/list/table/math reading, source disclosure and controls. Confirm syntax colors remain readable and never carry essential information alone.
6. Verify math with network unavailable. Instrument external URL/image/HTML TeX payloads, content rules and navigation denial. Test malformed/huge/recursive formulas and cancellation during rapid response changes. Confirm no unexpected requests occur.
7. Preserve the truthful scope: display math only, limited lexer and Markdown subset, no full-LaTeX or full-CommonMark claim.
