import SwiftUI

struct LocationToolView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var service = OneShotLocationService()
    @State private var copied = false
    var body: some View {
        Form {
            Section {
                Text("Request one location from iOS. Nothing happens until you tap below and allow access. Approximate location works too. Orivyn does not track you in the background, look up an address, or send this result to a model or server.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Get current location") { copied = false; service.request() }
                    .disabled(service.isBusy || scenePhase != .active).accessibilityIdentifier("location.request")
                if service.isBusy {
                    ProgressView("Waiting for iOS location…")
                    Button("Cancel request", role: .cancel) { service.cancel() }.accessibilityIdentifier("location.cancel")
                }
                if let error = service.error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            if let location = service.snapshot {
                Section("This request only") {
                    Text(String(format: "%.6f, %.6f", location.latitude, location.longitude))
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("location.coordinates")
                    LabeledContent("Accuracy", value: "±\(location.accuracy.formatted(.number.precision(.fractionLength(0)))) m")
                    LabeledContent("Measured", value: location.timestamp.formatted(date: .abbreviated, time: .standard))
                    Button(copied ? "Coordinates copied" : "Copy coordinates") {
                        UIPasteboard.general.setItems([["public.utf8-plain-text": String(format: "%.6f, %.6f", location.latitude, location.longitude)]],
                            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                        copied = true
                    }.accessibilityIdentifier("location.copy")
                    Button("Clear location", role: .destructive) { service.cancel(); copied = false }
                        .accessibilityIdentifier("location.clear")
                }
            }
            Section {
                Text("The displayed result is held in memory and cleared when you leave this screen or put Orivyn in the background. Copy is optional and places coordinates on this iPhone's clipboard for two minutes; anything you paste elsewhere is shared with that destination.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Location").navigationBarTitleDisplayMode(.inline)
            .onDisappear { service.cancel(); copied = false }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { service.cancel(); copied = false }
            }
    }
}
