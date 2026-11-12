import SwiftUI
import UIKit
import WebKit
import JavaScriptCore
import CryptoKit

/// New renderer for the next candidate. Intentionally not wired into MessageRow until native review.
/// Markdown is native SwiftUI. Only display math uses an offline, script-disabled MathML view.
struct RichMessageContent: View {
    private let document: MarkdownDocument
    @State private var pendingLink: URL?
    @State private var presentsLink = false
    @Environment(\.openURL) private var openURL

    init(text: String) { document = MarkdownDocument(source: text) }

    var body: some View {
        RichMarkdownBlocks(blocks: document.blocks)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                guard let allowed = MarkdownLinkPolicy.allowedURL(url.absoluteString) else { return .discarded }
                pendingLink = allowed
                presentsLink = true
                return .handled
            })
            .alert("Open external website?", isPresented: $presentsLink) {
                Button("Open website") {
                    if let pendingLink { openURL(pendingLink) }
                    pendingLink = nil
                }
                Button("Copy link") {
                    UIPasteboard.general.string = pendingLink?.absoluteString
                    pendingLink = nil
                }
                Button("Cancel", role: .cancel) { pendingLink = nil }
            } message: {
                Text(pendingLink?.absoluteString ?? "")
            }
    }
}

private struct RichMarkdownBlocks: View {
    let blocks: [MarkdownBlock]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in RichMarkdownBlockView(block: block) }
        }
    }
}

private struct RichMarkdownBlockView: View {
    let block: MarkdownBlock

    @ViewBuilder var body: some View {
        switch block.kind {
        case .paragraph(let source):
            RichInlineText(source: source)
        case .plainSource(let source, let reason):
            RichPlainSourceFallback(source: source, reason: reason)
        case .heading(let level, let source):
            RichInlineText(source: source)
                .font(level == 1 ? .title2.bold() : (level == 2 ? .title3.bold() : .headline))
                .accessibilityAddTraits(.isHeader)
                .padding(.top, level <= 2 ? 4 : 0)
        case .quote(let children):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.45)).frame(width: 3)
                AnyView(RichMarkdownBlocks(blocks: children))
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Block quote")
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker(item, ordered: ordered))
                            .monospacedDigit()
                            .frame(minWidth: 22, alignment: .trailing)
                            .accessibilityLabel(markerDescription(item, ordered: ordered))
                        AnyView(RichMarkdownBlocks(blocks: item.blocks))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        case .code(let code):
            RichCodeBlock(code: code)
        case .table(let table):
            RichMarkdownTable(table: table)
        case .thematicBreak:
            Divider().padding(.vertical, 4).accessibilityHidden(true)
        case .math(let math):
            RichDisplayMath(math: math)
        }
    }

    private func marker(_ item: MarkdownListItem, ordered: Bool) -> String {
        if let checked = item.isChecked { return checked ? "☑" : "☐" }
        return ordered ? "\(item.number ?? 1)." : "•"
    }

    private func markerDescription(_ item: MarkdownListItem, ordered: Bool) -> String {
        if let checked = item.isChecked { return checked ? "Completed item" : "Unchecked item" }
        return ordered ? "Item \(item.number ?? 1)" : "List item"
    }
}

/// A single viewport-backed text view replaces the entire rich tree on budget exhaustion.
/// It does not parse Markdown, detect links or shrink/truncate the stored source.
private struct RichPlainSourceFallback: View {
    let source: String
    let reason: MarkdownFallbackReason
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Plain-text view", systemImage: "doc.plaintext")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(reason.explanation + " The complete original source is below. Scroll to read or copy it all.")
                .font(.caption).foregroundStyle(.secondary)
            MarkdownPlainSourceTextView(source: source)
                .frame(height: 320)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            Button {
                UIPasteboard.general.string = source
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy full source", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("markdown.fallback.copy")
        }
        .accessibilityIdentifier("markdown.fallback")
        .onChange(of: source) { copied = false }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

private struct MarkdownPlainSourceTextView: UIViewRepresentable {
    let source: String

    func makeUIView(context: Context) -> UITextView {
        // TextKit 2 keeps text layout viewport-oriented rather than making one SwiftUI row per line.
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.dataDetectorTypes = []
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = "markdown.fallback.source"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != source { view.text = source }
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label
    }
}

private struct RichInlineText: View {
    let source: String
    var body: some View {
        Text(RichInlineMarkdown.attributed(source))
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum RichInlineMarkdown {
    static func attributed(_ source: String) -> AttributedString {
        // Escaping angle brackets makes raw HTML visible. Text cannot execute HTML or load images.
        let escaped = source.replacingOccurrences(of: "<", with: "\\<").replacingOccurrences(of: ">", with: "\\>")
        var value = (try? AttributedString(markdown: escaped, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
        let links = value.runs.compactMap { run -> (Range<AttributedString.Index>, URL)? in
            guard let link = run.link else { return nil }
            return (run.range, link)
        }
        for (range, link) in links where MarkdownLinkPolicy.allowedURL(link.absoluteString) == nil { value[range].link = nil }
        return value
    }
}

private struct RichCodeBlock: View {
    let code: MarkdownCodeBlock
    @State private var copied = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(code.language.isEmpty ? "Code" : code.language)
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code.text
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("markdown.code.copy")
                .disabled(code.text.isEmpty)
            }.padding(.horizontal, 12)
            Divider()
            ScrollView(.horizontal) {
                Text(highlighted)
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(14)
            }
            .accessibilityIdentifier("markdown.code.content")
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.15)))
        .onChange(of: code.text) { copied = false }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    private var highlighted: AttributedString {
        var result = AttributedString()
        for token in MarkdownSyntaxHighlighter.tokens(code.text, language: code.language) {
            var run = AttributedString(token.text)
            switch token.style {
            case .plain: run.foregroundColor = .primary
            case .keyword: run.foregroundColor = colorScheme == .dark ? Color(red: 0.94, green: 0.60, blue: 0.86) : Color(red: 0.55, green: 0.12, blue: 0.43)
            case .string: run.foregroundColor = colorScheme == .dark ? Color(red: 0.68, green: 0.87, blue: 0.62) : Color(red: 0.18, green: 0.39, blue: 0.12)
            case .number: run.foregroundColor = colorScheme == .dark ? Color(red: 0.92, green: 0.74, blue: 0.40) : Color(red: 0.53, green: 0.30, blue: 0.04)
            case .comment: run.foregroundColor = .secondary
            }
            result.append(run)
        }
        return result
    }
}

private struct RichMarkdownTable: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.headers.indices, id: \.self) { column in
                        cell(table.headers[column], column: column, header: true)
                    }
                }
                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table.headers.indices, id: \.self) { column in
                            cell(table.rows[row][column], column: column, header: false)
                                .accessibilityLabel("\(table.headers[column]): \(String(RichInlineMarkdown.attributed(table.rows[row][column]).characters))")
                        }
                    }
                    .background(row.isMultiple(of: 2) ? Color.secondary.opacity(0.04) : .clear)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2)))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table, \(table.headers.count) columns and \(table.rows.count) rows")
        .accessibilityIdentifier("markdown.table")
    }

    private func cell(_ source: String, column: Int, header: Bool) -> some View {
        Text(RichInlineMarkdown.attributed(source))
            .font(header ? .subheadline.weight(.semibold) : .subheadline)
            .textSelection(.enabled)
            .multilineTextAlignment(textAlignment(column))
            .padding(10)
            .frame(minWidth: 80, maxWidth: 280, alignment: alignment(column))
            .gridColumnAlignment(horizontalAlignment(column))
            .background(header ? Color.secondary.opacity(0.1) : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 0.5) }
            .accessibilityAddTraits(header ? .isHeader : [])
    }

    private func alignment(_ column: Int) -> Alignment {
        switch table.alignments[column] { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
    private func horizontalAlignment(_ column: Int) -> HorizontalAlignment {
        switch table.alignments[column] { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
    private func textAlignment(_ column: Int) -> TextAlignment {
        switch table.alignments[column] { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
}

// MARK: - Offline display math

enum OfflineMathResult: Equatable, Sendable {
    case rendered(String)
    case fallback(String)
}

/// Actor work executes away from the UI actor. JavaScriptCore has no browser/network/host bridge.
/// Only the SHA-256-verified bundled library is evaluated. TeX is passed as an argument, never code.
/// Limits bound normal work; JavaScriptCore exposes no supported Swift hard-timeout API. Cancelling
/// a view task discards stale output but cannot interrupt an already-running JS call.
actor OfflineMathRenderer {
    static let shared = OfflineMathRenderer()
    static let scriptSHA256 = "fa140498b8cfc8302cbe5e7cb1bdbc1f952bc38b3fa258ede09e73edbf9a74bc"
    private var script: String?

    func render(_ source: String) -> OfflineMathResult {
        guard !Task.isCancelled else { return .fallback("Math rendering cancelled.") }
        guard source.utf8.count <= 8_192 else { return .fallback("This expression is too long to typeset safely. TeX source is shown.") }
        guard let script = loadScript(), let context = JSContext() else {
            return .fallback("Offline math renderer is unavailable. TeX source is shown.")
        }
        context.evaluateScript(script)
        guard context.exception == nil,
              let katex = context.objectForKeyedSubscript("katex"), !katex.isUndefined,
              let function = katex.objectForKeyedSubscript("renderToString"), !function.isUndefined else {
            return .fallback("Offline math renderer could not start. TeX source is shown.")
        }
        let options: [String: Any] = [
            "displayMode": true, "output": "mathml", "throwOnError": true,
            "trust": false, "strict": "error", "maxExpand": 100, "maxSize": 10,
            "macros": [String: String]()
        ]
        // A fresh context and macros object for each expression prevent cross-message macro state.
        let output = function.call(withArguments: [source, options])
        guard context.exception == nil, let html = output?.toString(), html.contains("<math"), html.utf8.count <= 500_000 else {
            return .fallback("This expression could not be typeset. TeX source is shown.")
        }
        guard !Task.isCancelled else { return .fallback("Math rendering cancelled.") }
        return .rendered(html)
    }

    private func loadScript() -> String? {
        if let script { return script }
        guard let url = Bundle.main.url(forResource: "katex-0.19.1.min", withExtension: "js"),
              let data = try? Data(contentsOf: url),
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == Self.scriptSHA256,
              let value = String(data: data, encoding: .utf8) else { return nil }
        script = value
        return value
    }
}

private struct RichDisplayMath: View {
    let math: MarkdownMathBlock
    @State private var result: OfflineMathResult?
    @State private var height: CGFloat = 64
    @State private var webFailure = false
    @State private var showsSource = false
    @State private var copied = false
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .rendered(let markup) = result, !webFailure {
                OfflineMathWebView(markup: markup, fontSize: fontSize, height: $height, failed: $webFailure)
                    .frame(height: min(500, max(44, height)))
                    .accessibilityIdentifier("markdown.math.rendered")
                DisclosureGroup("TeX source", isExpanded: $showsSource) { sourceText }
                    .font(.caption)
            } else {
                sourceText
                if case .fallback(let reason) = result {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                } else if webFailure {
                    Text("Math display is unavailable. TeX source is shown.").font(.caption).foregroundStyle(.secondary)
                } else if !math.isClosed {
                    Text("Waiting for the end of this expression.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                UIPasteboard.general.string = math.source
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy TeX", systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption)
            }
            .buttonStyle(.plain).padding(.vertical, 4)
            .disabled(math.source.isEmpty)
            .accessibilityIdentifier("markdown.math.copy")
        }
        .task(id: math) {
            result = nil
            webFailure = false
            copied = false
            guard math.isClosed else { return }
            let next = await OfflineMathRenderer.shared.render(math.source)
            guard !Task.isCancelled else { return }
            result = next
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    private var sourceText: some View {
        Text(verbatim: math.source)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .accessibilityLabel("TeX source: \(math.source)")
            .accessibilityIdentifier("markdown.math.source")
    }
}

/// Only verified-renderer HTML reaches the template. No model HTML, navigation, remote resources,
/// or executable page scripts are permitted. MathML uses WebKit's built-in math layout and fonts.
private struct OfflineMathWebView: UIViewRepresentable {
    let markup: String
    let fontSize: CGFloat
    @Binding var height: CGFloat
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(height: $height, failed: $failed) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.bounces = false
        view.navigationDelegate = context.coordinator
        view.allowsLinkPreview = false
        context.coordinator.observe(view)
        context.coordinator.installBlocker(on: view)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.height = $height
        context.coordinator.failed = $failed
        context.coordinator.setContent(markup, fontSize: fontSize, on: uiView)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        coordinator.observation?.invalidate()
        coordinator.observation = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var failed: Binding<Bool>
        var observation: NSKeyValueObservation?
        private var blockerReady = false
        private var currentHTML: String?
        private var loadedHTML: String?

        init(height: Binding<CGFloat>, failed: Binding<Bool>) { self.height = height; self.failed = failed }

        func observe(_ view: WKWebView) {
            observation = view.scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, change in
                guard let size = change.newValue, size.height.isFinite, size.height > 0 else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let bounded = min(500, max(44, size.height))
                    if abs(self.height.wrappedValue - bounded) > 1 { self.height.wrappedValue = bounded }
                }
            }
        }

        func installBlocker(on view: WKWebView) {
            let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
            Task { @MainActor [weak self, weak view] in
                guard let self, let view else { return }
                do {
                    let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "JarvisEVOOfflineMathDenyAll", encodedContentRuleList: rules)
                    guard !Task.isCancelled else { return }
                    view.configuration.userContentController.add(list)
                    self.blockerReady = true
                    self.loadIfReady(view)
                } catch { self.failed.wrappedValue = true }
            }
        }

        func setContent(_ markup: String, fontSize: CGFloat, on view: WKWebView) {
            let size = min(60, max(12, fontSize))
            currentHTML = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src 'none'; font-src 'none'; connect-src 'none'; object-src 'none'; media-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">
            <style>:root{color-scheme:light dark}html,body{margin:0;padding:0;background:transparent;color:CanvasText}body{font-size:\(size)px;padding:8px;box-sizing:border-box}math{font-size:1em}annotation{display:none}</style>
            </head><body>\(markup)</body></html>
            """
            loadIfReady(view)
        }

        private func loadIfReady(_ view: WKWebView) {
            guard blockerReady, let currentHTML, currentHTML != loadedHTML else { return }
            loadedHTML = currentHTML
            view.loadHTMLString(currentHTML, baseURL: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let isInitialDocument = navigationAction.navigationType == .other && navigationAction.request.url?.absoluteString == "about:blank"
            decisionHandler(isInitialDocument ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed.wrappedValue = true }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed.wrappedValue = true }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failed.wrappedValue = true }
    }
}
