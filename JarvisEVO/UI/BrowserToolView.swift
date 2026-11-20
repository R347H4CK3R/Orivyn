import SwiftUI
import SafariServices

struct BrowserToolView: View {
    var passageExplanation: PassageExplanationView? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var address = ""
    @State private var bookmarks = WebBookmarkStore()
    @State private var destination: BrowserPresentation?
    @State private var copiedCleanLink: String?
    @State private var error: String?
    @FocusState private var addressFocused: Bool

    private var validationError: String? {
        do { _ = try WebNavigationDraft.validated(address); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        Form {
            Section {
                Text("Open an HTTPS website in Apple's Safari view. The website receives your visit and normal browsing information. Orivyn cannot read the page, website passwords or browsing history, and does not give page content to a model.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Search or website") {
                TextField("Search or enter https://…", text: $address).keyboardType(.webSearch)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($addressFocused)
                    .accessibilityLabel("Search words or HTTPS website address").accessibilityIdentifier("browser.url")
                if addressFocused {
                    Button("Done typing") { addressFocused = false }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("browser.finishEditing")
                }
                Text("Search words go to DuckDuckGo only when you tap Search DuckDuckGo. Your chats and drafts are never included. Do not search for passwords or private tokens.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let draft = try? WebNavigationDraft.validated(address) {
                    Text(draft.isWebsite ? "Opens: " + (draft.destination.url.host ?? "website") : "Searches DuckDuckGo for the words above")
                        .font(.subheadline).accessibilityIdentifier("browser.destination")
                }
                if !address.isEmpty, let validationError { Text(validationError).font(.footnote).foregroundStyle(.red) }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            if let cleanLink = try? WebCleanLink.validated(address) {
                Section("Web tools") {
                    Button {
                        guard destination == nil, scenePhase == .active else { return }
                        do {
                            let checked = try BrowserPresentation.validated(address, reader: true)
                            addressFocused = false
                            error = nil
                            destination = checked
                        } catch { self.error = error.localizedDescription }
                    } label: {
                        Label("Open in Reader", systemImage: "doc.text")
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.borderless)
                        .disabled(destination != nil || scenePhase != .active)
                        .accessibilityIdentifier("browser.reader")
                    Text("Reader asks Safari for a simpler reading view when the website supports it. Otherwise Safari opens the normal page.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Clean link removes known tracking tags only. Functional parameters and page sections stay intact. This URL may still contain private information, including tokens. Review exactly what will be copied:")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(cleanLink).font(.caption).textSelection(.enabled)
                        .accessibilityIdentifier("browser.cleanLink.preview")
                    Button {
                        guard destination == nil, scenePhase == .active else { return }
                        // Explicit local-only write. No clipboard read or automatic copy.
                        UIPasteboard.general.setItems([["public.utf8-plain-text": cleanLink]],
                            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
                        copiedCleanLink = cleanLink
                    } label: {
                        Label("Copy Clean Link", systemImage: "doc.on.doc")
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.borderless)
                        .disabled(destination != nil || scenePhase != .active)
                        .accessibilityIdentifier("browser.cleanLink.copy")
                    if copiedCleanLink == cleanLink {
                        Text("Copied this cleaned link for five minutes. The original page address is unchanged.")
                            .font(.footnote).accessibilityIdentifier("browser.cleanLink.copied")
                    }
                }
            }
            if let passageExplanation {
                Section {
                    NavigationLink {
                        passageExplanation
                    } label: {
                        Label("Explain a passage", systemImage: "text.magnifyingglass")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("browser.explain")
                } footer: {
                    Text("Paste a passage to explain with an installed model. Nothing is taken directly from the website.")
                }
            }
            Section("Bookmarks · On this iPhone") {
                Text("Bookmarks use the address you enter above, not pages visited inside Safari. Save only if this address is safe to keep on this iPhone. Bookmarks keep the HTTPS address and path, but remove query text and page sections; some links may work differently. No browsing history is saved by Orivyn.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let savedAddress = try? WebBookmarkStore.bookmarkAddress(address) {
                    Text(savedAddress).font(.caption).textSelection(.enabled)
                    Button {
                        addressFocused = false
                        do { try bookmarks.saveWebsite(address); error = nil }
                        catch { self.error = error.localizedDescription }
                    } label: {
                        Label("Save bookmark", systemImage: "bookmark")
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.borderless).accessibilityIdentifier("browser.bookmark.save")
                }
                ForEach(bookmarks.bookmarks, id: \.self) { bookmark in
                    HStack {
                        Button {
                            // End editing before changing the field so focus does not
                            // scroll the bookmark actions out of the user's viewport.
                            addressFocused = false
                            address = bookmark; error = nil
                        } label: {
                            Text(bookmark).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(.borderless)
                            .accessibilityIdentifier("browser.bookmark.fill.\(bookmark)")
                            .accessibilityLabel("Fill address from bookmark " + bookmark)
                        Spacer()
                        Button {
                            addressFocused = false
                            bookmarks.remove(bookmark)
                        } label: {
                            Label("Remove", systemImage: "trash").labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("browser.bookmark.remove.\(bookmark)")
                            .accessibilityLabel("Remove bookmark " + bookmark)
                    }
                }
                if bookmarks.bookmarks.isEmpty { Text("No bookmarks yet.").foregroundStyle(.secondary) }
            }
            Section {
                Text("Only HTTPS addresses without embedded credentials are accepted. Do not put passwords or tokens in URLs; websites and browsers may retain them. Links followed inside Safari are controlled by Safari and the destination website.")
                Text("Done returns to this unchanged address and your conversation draft. This is a browser view, not an autonomous browsing agent or an account connection.")
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Web").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button((try? WebNavigationDraft.validated(address).actionTitle) ?? "Go") {
                    guard destination == nil, scenePhase == .active else { return }
                    do {
                        let checked = try BrowserPresentation.validated(address)
                        addressFocused = false
                        error = nil
                        destination = checked
                    } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("browser.open")
                    .disabled(validationError != nil || destination != nil || scenePhase != .active)
            }
        }
        .sheet(item: $destination) { opened in
            SafariBrowser(destination: opened.destination, prefersReader: opened.prefersReader) {
                guard destination?.id == opened.id else { return }
                destination = nil
            }.ignoresSafeArea()
        }
    }
}

private struct SafariBrowser: UIViewControllerRepresentable {
    let destination: BrowserDestination
    let prefersReader: Bool
    let completed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = prefersReader
        let controller = SFSafariViewController(url: destination.url, configuration: configuration)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .done
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    // UIKit delivers this UI completion on the main thread. The SDK's legacy
    // delegate protocol is nonisolated; retain runtime main-actor checking.
    @MainActor final class Coordinator: NSObject, @preconcurrency SFSafariViewControllerDelegate {
        private let completed: () -> Void
        private var didComplete = false
        init(completed: @escaping () -> Void) { self.completed = completed }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            guard !didComplete else { return }
            didComplete = true
            completed()
        }
    }
}
