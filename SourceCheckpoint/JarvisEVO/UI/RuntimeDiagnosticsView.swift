import SwiftUI

/// View-lifetime sampling, not a background service or model heartbeat.
struct RuntimeDiagnosticsView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var log = RuntimeDiagnosticLog()
    var body: some View {
        List {
            Section("Current observation") {
                if let state = log.events.last?.state { rows(state) }
                if let checked = log.lastChecked { LabeledContent("Last checked", value: checked.formatted(date: .omitted, time: .standard)) }
                if let changed = log.lastChanged { LabeledContent("Last observed change", value: changed.formatted(date: .omitted, time: .standard)) }
                Button("Refresh now") { sample() }
            }
            Section {
                Text("Refreshes every 30 seconds while this screen is open and the app is active. An unchanged state does not prove a stall. Network reachability does not verify a provider connection. Character count is observed output, not an estimate of completion.")
                Text("This local session keeps at most 200 state changes. It does not record conversation text, file names, endpoint addresses or credentials, and sends nothing anywhere. Closing this screen discards its log.")
            }
            Section("Observed state changes") {
                ForEach(log.events.reversed()) { event in
                    DisclosureGroup(event.date.formatted(date: .omitted, time: .standard)) { rows(event.state) }
                }
            }
        }
        .navigationTitle("Live diagnostics")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                sample()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
    @MainActor private func sample() { log.observe(model.runtimeDiagnosticState) }
    @ViewBuilder private func rows(_ state: RuntimeDiagnosticState) -> some View {
        LabeledContent("Response generation", value: state.generating ? "Active" : "Idle")
        LabeledContent("Observed response characters", value: String(state.generatedCharacters))
        LabeledContent("Automatic model preparation", value: state.preparingModel ? "Active" : "Idle")
        LabeledContent("Model download", value: state.downloadPercent.map { "\($0)% received" } ?? "No reported transfer")
        LabeledContent("Installed model records", value: String(state.installedModelCount))
        LabeledContent("Attachment import", value: state.importingAttachments ? "Active" : "Idle")
        LabeledContent("Image save", value: state.savingImage ? "Active" : "Idle")
        LabeledContent("Heavy-work owner", value: state.heavyWork)
        LabeledContent("Heavy-work phase", value: state.heavyPhase)
        LabeledContent("New inference blocked", value: state.admissionBlocked ? "Yes" : "No")
        LabeledContent("Network path", value: state.online.map { $0 ? "Available" : "Unavailable" } ?? "Unknown")
        LabeledContent("Current error notification", value: state.hasReportedError ? "Present; review the app alert" : "None")
    }
}
