import SwiftUI
import SafariServices

struct BrowserToolView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var address = ""
    @State private var destination: BrowserDestination?
    @State private var error: String?
    @FocusState private var addressFocused: Bool

    private var validationError: String? {
        do { _ = try BrowserDestination.validated(address); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        Form {
            Section {
                Text("Open an HTTPS website in Apple's Safari view. The website receives your visit and normal browsing information. Orivyn cannot read the page, website passwords or browsing history, and does not give page content to a model.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Website") {
                TextField("https://example.com", text: $address).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($addressFocused)
                    .accessibilityLabel("Website address").accessibilityIdentifier("browser.url")
                if !address.isEmpty, let validationError { Text(validationError).font(.footnote).foregroundStyle(.red) }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            Section {
                Text("Only HTTPS addresses without embedded credentials are accepted. Do not put passwords or tokens in URLs; websites and browsers may retain them. Links followed inside Safari are controlled by Safari and the destination website.")
                Text("Done returns to this unchanged address and your conversation draft. This is a browser view, not an autonomous browsing agent or an account connection.")
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Browser").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Open") {
                    guard destination == nil, scenePhase == .active else { return }
                    do {
                        let checked = try BrowserDestination.validated(address)
                        addressFocused = false
                        error = nil
                        destination = checked
                    } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("browser.open")
                    .disabled(validationError != nil || destination != nil || scenePhase != .active)
            }
        }
        .sheet(item: $destination) { opened in
            SafariBrowser(destination: opened) {
                guard destination?.id == opened.id else { return }
                destination = nil
            }.ignoresSafeArea()
        }
    }
}

private struct SafariBrowser: UIViewControllerRepresentable {
    let destination: BrowserDestination
    let completed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: destination.url, configuration: configuration)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .done
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, SFSafariViewControllerDelegate {
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
