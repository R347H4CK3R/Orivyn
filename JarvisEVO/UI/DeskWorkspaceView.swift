import SwiftUI

/// Read-only app-owned external content. It never embeds or controls another iOS app.
struct DeskWorkspaceView: View {
    @Bindable var controller: ExternalWorkspaceController
    @State private var scrollPosition = ScrollPosition(idType: UUID.self, edge: .top)
    @State private var scrollMetrics = DeskScrollMetrics()
    var body: some View {
        Group {
            if controller.state.isSharing && controller.state.isForeground, let model = controller.model {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        EvoMark(size: 42)
                        Text("Orivyn Desk").font(.largeTitle.weight(.semibold))
                        Spacer()
                        Text(controller.state.selectedPanel.title).font(.title2).foregroundStyle(.secondary)
                    }
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            switch controller.state.selectedPanel {
                            case .conversation:
                                if let conversation = model.activeConversation {
                                    Text(conversation.title).font(.title)
                                    ForEach(conversation.messages) { message in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(message.role == .user ? "You" : "Jarvis").font(.headline)
                                            Text(message.content).font(.title3).frame(maxWidth: .infinity, alignment: .leading)
                                        }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                                    }
                                } else { Text("Choose a conversation on your iPhone.").font(.title2) }
                            case .projects:
                                if model.workspace.projects.isEmpty { Text("No projects yet. Create one on your iPhone.").font(.title2) }
                                ForEach(model.workspace.projects) { project in
                                    Label(project.name, systemImage: "folder").font(.title2)
                                }
                            case .models:
                                Text("Installed on this iPhone").font(.title)
                                if model.installedModels.isEmpty { Text("No downloaded models.") }
                                ForEach(model.installedModels) { item in
                                    HStack { Text(item.name); Spacer(); Text(item.formattedSize).foregroundStyle(.secondary) }.font(.title2)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollPosition($scrollPosition)
                    .onScrollGeometryChange(for: DeskScrollMetrics.self) { geometry in
                        DeskScrollMetrics(offset: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
                            viewport: geometry.containerSize.height,
                            maximum: max(0, geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom - geometry.containerSize.height))
                    } action: { _, metrics in scrollMetrics = metrics }
                    .onChange(of: controller.state.scrollRequest?.id) { _, _ in
                        guard let action = controller.state.scrollRequest?.action else { return }
                        switch action {
                        case .top: scrollPosition.scrollTo(edge: .top)
                        case .bottom: scrollPosition.scrollTo(edge: .bottom)
                        case .up: scrollPosition.scrollTo(y: max(0, scrollMetrics.offset - scrollMetrics.viewport * 0.75))
                        case .down: scrollPosition.scrollTo(y: min(scrollMetrics.maximum, scrollMetrics.offset + scrollMetrics.viewport * 0.75))
                        }
                    }
                    .onChange(of: controller.state.selectedPanel) { _, _ in scrollPosition.scrollTo(edge: .top) }
                    Text("Controlled from your iPhone · Hide display to protect your workspace").font(.footnote).foregroundStyle(.secondary)
                }.padding(40)
            } else {
                VStack(spacing: 20) {
                    EvoMark(size: 76)
                    Text("Orivyn Desk").font(.largeTitle.weight(.semibold))
                    Label("Workspace hidden", systemImage: "lock.fill").font(.title2)
                    Text("Choose Show workspace on your iPhone to reveal content here.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground)).foregroundStyle(.primary)
    }
}

struct DeskControlView: View {
    @Bindable var controller: ExternalWorkspaceController
    var body: some View {
        Form {
            Section {
                if controller.state.isConnected {
                    Label("External display connected", systemImage: "display")
                        .accessibilityIdentifier("desk.connected")
                } else {
                    Text("No external display connected").accessibilityIdentifier("desk.disconnected")
                }
                Toggle("Show workspace", isOn: Binding(get: { controller.state.isSharing }, set: {
                    if $0 { controller.startSharing() } else { controller.stopSharing() }
                })).disabled(!controller.state.canStartSharing).accessibilityIdentifier("desk.enabled")
                Picker("Panel", selection: Binding(get: { controller.state.selectedPanel }, set: { controller.select($0) })) {
                    ForEach(DeskPanel.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("desk.panel")
            } header: { Text("Display privacy") } footer: {
                Text("Showing a workspace reveals the selected conversation, project names or installed models to everyone viewing the display. Connecting, disconnecting or leaving the app hides it. Return here to reveal it again.")
            }
            Section("Scroll the display") {
                HStack {
                    Button("Top", systemImage: "arrow.up.to.line") { controller.scroll(.top) }
                    Spacer()
                    Button("Up", systemImage: "arrow.up") { controller.scroll(.up) }
                    Spacer()
                    Button("Down", systemImage: "arrow.down") { controller.scroll(.down) }
                        .accessibilityIdentifier("desk.scroll.down")
                    Spacer()
                    Button("Latest", systemImage: "arrow.down.to.line") { controller.scroll(.bottom) }
                }.buttonStyle(.borderless).disabled(!controller.state.isSharing)
                Text("Use Up and Down to reach long content. Latest follows the bottom of the selected panel. Scrolling never turns on sharing.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Connect a display") {
                Text("Use a compatible USB-C DisplayPort or HDMI adapter and display. iPhone 16 Plus supports video output; actual resolution depends on your display, cable and adapter. The phone remains the controller.")
                Text("This is an Orivyn-only, read-only workspace, not a replacement for iOS. It cannot embed other installed apps. Resizable desktop windows, a computer terminal and remote desktop are not provided by this view.")
                Text("Physical HDMI, reconnect, lock and resolution validation is still pending. A simulator without an external scene must remain disconnected.")
            }.font(.footnote).foregroundStyle(.secondary)
            Section("Display preview") {
                DeskWorkspaceView(controller: controller).frame(height: 280).clipped()
                    .accessibilityIdentifier("desk.preview")
            }
        }.navigationTitle("Orivyn Desk").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("desk.title")
    }
}

private struct DeskScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var viewport: CGFloat = 0
    var maximum: CGFloat = 0
}
