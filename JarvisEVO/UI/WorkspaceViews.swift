import SwiftUI

struct OrivynWorkspaceView: View {
    @Bindable var model: AppModel
    let section: WorkspaceSection
    let openMenu: () -> Void
    let openChat: () -> Void
    let openModels: () -> Void
    var body: some View {
        NavigationStack {
            content.navigationTitle(section.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: openMenu) { EvoMenuGlyph().frame(width: 21, height: 21) }
                            .accessibilityLabel("Open navigation").accessibilityIdentifier("workspace.menu")
                    }
                }.toolbarBackground(.hidden, for: .navigationBar)
                .background(Color(uiColor: .systemBackground))
        }
    }
    @ViewBuilder private var content: some View {
        switch section {
        case .chat: EmptyView()
        case .space, .images:
            LocalSpaceView(model: model, imagesOnly: section == .images, openChat: openChat).id(section)
        case .projects: LocalProjectsView(model: model, openChat: openChat)
        case .customize: CustomizeWorkspaceView(model: model, openModels: openModels)
        case .plugins: IntegrationCatalogView(broker: model.plugins, setupError: model.pluginSetupError)
        case .studio:
            CapabilityNoticeView(title: "Local tasks and code", icon: "chevron.left.forwardslash.chevron.right",
                detail: "Run bounded read-only tasks on your iPhone, or ask your model to explain and write code. Code still needs testing; Orivyn does not claim to build or publish its own fixes.") {
                NavigationLink("Verified local reads") { VerifiedLocalReadView(model: model) }.accessibilityIdentifier("verified.open")
                NavigationLink("Experimental model tasks") { LocalAgentView(model: model) }.accessibilityIdentifier("agent.open")
                Button("Start coding conversation") {
                    if model.draft.isEmpty { model.draft = "Help me with this coding task: " }; openChat()
                }.buttonStyle(.borderedProminent)
            }
        case .sites:
            CapabilityNoticeView(title: "Build an idea into a site", icon: "square.grid.2x2",
                detail: "Your local model can draft website code in chat. Hosted sites, publishing and shared-site accounts are not integrated in this build.") {
                Button("Draft website code") {
                    if model.draft.isEmpty { model.draft = "Help me create a website for: " }; openChat()
                }.buttonStyle(.borderedProminent)
            }
        case .scheduled:
            ScheduledRemindersView()
        }
    }
}

private struct LocalLibraryEntry: Identifiable {
    let attachment: ChatAttachment
    let conversationID: UUID
    let conversationTitle: String
    var id: UUID { attachment.id }
}

struct LocalSpaceView: View {
    @Bindable var model: AppModel
    var imagesOnly = false
    let openChat: () -> Void
    @State private var query = ""
    @State private var filter = "All"
    @State private var preview: ChatAttachment?
    @State private var visionImage: ChatAttachment?
    @State private var error: String?
    @State private var showsImageCreation = false
    @State private var imageLeaseID: UUID?
    private var entries: [LocalLibraryEntry] {
        var seen: Set<UUID> = []
        let all = model.conversations.sorted { $0.updatedAt > $1.updatedAt }.flatMap { chat in
            chat.messages.flatMap { message in
                message.attachments.compactMap { attachment -> LocalLibraryEntry? in
                    guard seen.insert(attachment.id).inserted else { return nil }
                    return LocalLibraryEntry(attachment: attachment, conversationID: chat.id, conversationTitle: chat.title)
                }
            }
        }
        return all.filter { entry in
            (!imagesOnly || entry.attachment.isImage)
                && (filter != "Favorites" || model.workspace.isFavorite(entry.id))
                && (filter != "Documents" || !entry.attachment.isImage)
                && (filter != "Images" || entry.attachment.isImage)
                && (query.isEmpty || entry.attachment.name.localizedCaseInsensitiveContains(query)
                    || entry.conversationTitle.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(imagesOnly ? ["All", "Favorites"] : ["All", "Favorites", "Documents", "Images"], id: \.self) { value in
                        Button(value) { filter = value }
                            .font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 9)
                            .background(filter == value ? Color.primary.opacity(0.16) : Color.clear, in: Capsule())
                            .accessibilityAddTraits(filter == value ? .isSelected : [])
                            .accessibilityIdentifier("workspace.filter.\(value)")
                    }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
            if imagesOnly {
                Text("Images saved on this iPhone. Create uses the supported Apple Image Playground sheet only after your explicit choice.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 8)
                Button("Create an image", systemImage: "sparkles") {
                    guard model.canBeginHeavyWork, imageLeaseID == nil else { return }
                    if model.generatedImageStager != nil { imageLeaseID = UUID(); showsImageCreation = true }
                    else { error = "Private image storage is unavailable. Reopen Orivyn and try again." }
                }.buttonStyle(.bordered).accessibilityIdentifier("image.create")
                    .disabled(!model.canBeginHeavyWork || imageLeaseID != nil)
                if model.isSavingGeneratedImage { ProgressView("Saving accepted image…").font(.caption) }
            }
            if entries.isEmpty {
                ContentUnavailableView(query.isEmpty ? "Your files belong here" : "No matching files",
                    systemImage: imagesOnly ? "photo.on.rectangle" : "square.stack.3d.up",
                    description: Text("Attachments from saved conversations appear here. Original files stay on this iPhone; restoring a text backup does not restore file bytes."))
            } else {
                List(entries) { entry in
                    HStack(spacing: 12) {
                        Button { preview = entry.attachment } label: {
                            HStack(spacing: 12) {
                                Image(systemName: entry.attachment.isImage ? "photo" : "doc.text")
                                    .frame(width: 42, height: 48).background(Color.evoSurface, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.attachment.name).lineLimit(2).foregroundStyle(.primary)
                                    Text(entry.conversationTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.attachment.byteCount), countStyle: .file))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        if entry.attachment.isImage {
                            Button { visionImage = entry.attachment } label: { Image(systemName: "eye") }
                                .buttonStyle(.borderless).accessibilityLabel("Analyze image")
                                .accessibilityIdentifier("vision.analyze.\(entry.attachment.id)")
                        }
                        Button {
                            do { try model.workspace.toggleFavorite(entry.id) } catch { self.error = error.localizedDescription }
                        } label: { Image(systemName: model.workspace.isFavorite(entry.id) ? "star.fill" : "star") }
                            .buttonStyle(.borderless).accessibilityLabel(model.workspace.isFavorite(entry.id) ? "Remove favorite" : "Favorite file")
                    }.padding(.vertical, 4).listRowSeparator(.hidden)
                        .contextMenu {
                            if entry.attachment.isImage {
                                Button("Analyze image", systemImage: "eye") { visionImage = entry.attachment }
                            }
                            Button("Open conversation", systemImage: "bubble.left") { model.selectConversation(entry.conversationID); openChat() }
                        }
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }.safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                TextField(imagesOnly ? "Search images" : "Search files", text: $query)
                Button(action: openChat) { Image(systemName: "plus").frame(width: 32, height: 32) }.accessibilityLabel("Add a file in chat")
            }.padding(12).background(Color.evoSurface, in: Capsule()).padding(16)
        }
        .sheet(item: $preview) { attachment in
            AttachmentPreviewView(attachment: attachment, originalURL: model.attachmentService.url(for: attachment),
                                  previewURL: model.attachmentService.previewURL(for: attachment))
        }
        .sheet(item: $visionImage) { attachment in
            VisionAnalysisView(model: model, attachment: attachment, originalURL: model.attachmentService.url(for: attachment))
        }
        .sheet(isPresented: $showsImageCreation, onDismiss: {
            // This stable outer presenter owns release, not the nested Apple sheet.
            if let id = imageLeaseID { model.endHeavyWork(id: id) }
            imageLeaseID = nil
        }) {
            if let stager = model.generatedImageStager, let id = imageLeaseID {
                ImageCreationView(model: model, leaseID: id, stager: stager) { url, concept in
                    model.acceptGeneratedImage(url, concept: concept, stager: stager)
                }
            }
        }
        .alert("Could not update your library", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct LocalProjectsView: View {
    @Bindable var model: AppModel
    let openChat: () -> Void
    @State private var query = ""
    @State private var projectName = ""
    @State private var adding = false
    @State private var error: String?
    private var projects: [WorkspaceProject] { model.workspace.projects.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack {
            if let error = model.workspace.loadError { Text(error).font(.footnote).foregroundStyle(.red).padding() }
            if projects.isEmpty {
                ContentUnavailableView("Your projects", systemImage: "folder", description: Text("Organize conversations together on this iPhone."))
            } else {
                List(projects) { project in
                    NavigationLink { ProjectConversationsView(model: model, project: project, openChat: openChat) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder").frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name)
                                Text("\(model.conversations.filter { model.workspace.projectID(for: $0.id) == project.id }.count) conversations")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }.listRowSeparator(.hidden)
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New project").accessibilityIdentifier("workspace.project.new")
                    .disabled(model.workspace.loadError != nil)
            }
        }.safeAreaInset(edge: .bottom) {
            HStack { Image(systemName: "magnifyingglass"); TextField("Search projects", text: $query) }
                .padding(12).background(Color.evoSurface, in: Capsule()).padding(16)
        }.alert("New project", isPresented: $adding) {
            TextField("Project name", text: $projectName)
            Button("Cancel", role: .cancel) { projectName = "" }
            Button("Create") {
                do { try model.workspace.addProject(name: projectName); projectName = "" }
                catch { self.error = error.localizedDescription }
            }.disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || projectName.count > 80)
        } message: { Text("Projects organize chats on this iPhone.") }
        .alert("Could not save project", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}

private struct ProjectConversationsView: View {
    @Bindable var model: AppModel
    let project: WorkspaceProject
    let openChat: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var deleting = false
    @State private var error: String?
    private var chats: [Conversation] { model.conversations.filter { model.workspace.projectID(for: $0.id) == project.id } }
    var body: some View {
        List {
            Section {
                Button("Add existing conversations", systemImage: "plus") { choosing = true }
                ForEach(chats) { chat in
                    Button { model.selectConversation(chat.id); openChat() } label: {
                        Label(chat.title, systemImage: chat.isArchived ? "archivebox" : "bubble.left").foregroundStyle(.primary)
                    }
                }
                if chats.isEmpty { Text("No conversations in this project yet.").foregroundStyle(.secondary) }
            }
            Section { Button("Delete project", role: .destructive) { deleting = true } }
            footer: { Text("Removing a project keeps all of its conversations.") }
        }.navigationTitle(project.name)
            .sheet(isPresented: $choosing) {
                NavigationStack {
                    List(model.conversations) { chat in
                        Button {
                            do { try model.workspace.assign(chat.id, to: model.workspace.projectID(for: chat.id) == project.id ? nil : project.id) }
                            catch { choosing = false; self.error = error.localizedDescription }
                        } label: {
                            HStack {
                                Text(chat.title).foregroundStyle(.primary); Spacer()
                                if model.workspace.projectID(for: chat.id) == project.id { Image(systemName: "checkmark") }
                            }
                        }
                    }.navigationTitle("Add conversations").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { choosing = false } } }
                }
            }.confirmationDialog("Delete this project? Conversations will be kept.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete project", role: .destructive) {
                    do { try model.workspace.deleteProject(project.id); dismiss() } catch { self.error = error.localizedDescription }
                }
            }.alert("Could not update project", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
}

struct CustomizeWorkspaceView: View {
    @Bindable var model: AppModel
    let openModels: () -> Void
    var body: some View {
        Form {
            if let error = model.workspace.loadError { Section { Text(error).foregroundStyle(.red) } }
            Section {
                NavigationLink { IntegrationCatalogView(broker: model.plugins, setupError: model.pluginSetupError).navigationTitle("Plugins") } label: { row("Plugins", icon: "puzzlepiece.extension", color: .mint, detail: "Local tools") }
                NavigationLink { MemoryView(model: model) } label: { row("Memory", icon: "book.closed", color: .orange, detail: "\(model.memories.count) notes") }
                NavigationLink { BehaviorEditorView(workspace: model.workspace) } label: { row("Behavior", icon: "sparkle", color: .cyan, detail: model.workspace.behavior.style) }
            }
            Section {
                ForEach(["Email", "Calendar", "Passwords", "Health", "Finances"], id: \.self) { title in
                    NavigationLink { IntegrationDetailView(title: title) } label: { row(title, icon: IntegrationDetailView.icon(for: title), color: IntegrationDetailView.color(for: title), detail: IntegrationDetailView.status(for: title)) }
                }
            }
            Section {
                NavigationLink { LocalDeviceView(model: model) } label: { row("Devices", icon: "desktopcomputer", color: .blue, detail: "This iPhone") }
                NavigationLink { IntegrationDetailView(title: "Browser") } label: { row("Browser", icon: "network", color: .blue, detail: "Open a website") }
                NavigationLink { IntegrationDetailView(title: "Location") } label: { row("Location", icon: "location", color: .purple, detail: "One-time request") }
            }
            Section("On this iPhone") {
                NavigationLink { CalculatorView() } label: { row("Calculator", icon: "number", color: .green, detail: "Offline arithmetic") }
                NavigationLink { ShortcutsHelpView() } label: { row("Shortcuts & sharing", icon: "square.and.arrow.up", color: .purple, detail: "Review first") }
                NavigationLink { ScheduledRemindersView().navigationTitle("Scheduled") } label: { row("Local reminders", icon: "bell", color: .orange, detail: "One-time alerts") }
            }
            Section("On-device intelligence") {
                Button(action: openModels) { row("Models", icon: "cpu", color: .blue, detail: "\(model.installedModels.count) installed") }
                NavigationLink { RemoteSettingsView(model: model) } label: { row("Optional endpoint", icon: "network", color: .gray, detail: model.remoteEnabled ? "Enabled" : "Off") }
            }
            Section {
                Text("Orivyn has no subscriptions, pay tiers or in-app unlocks. Local models run free on your device. Optional external services can have their own fees; none are enabled automatically.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationBarTitleDisplayMode(.inline)
    }
    private func row(_ title: String, icon: String, color: Color, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 22); Text(title).foregroundStyle(.primary); Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.padding(.vertical, 5)
    }
}

struct BehaviorEditorView: View {
    let workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ResponseBehavior()
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Label("Behavior", systemImage: "sparkle").font(.headline)
                Text("Choose how Orivyn responds. Preferences are supplied to your selected model; small models may not follow every instruction reliably.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("How Orivyn responds") {
                TextEditor(text: $draft.instructions).frame(minHeight: 110).accessibilityLabel("Response instructions").accessibilityIdentifier("behavior.instructions")
                Text("\(draft.instructions.utf8.count)/\(ResponseBehavior.instructionByteLimit) UTF-8 bytes").font(.caption).foregroundStyle(.secondary)
                if draft.instructions.utf8.count > ResponseBehavior.instructionByteLimit {
                    Text("Your previous instructions were preserved. Shorten them to save and leave room for local replies.").font(.footnote).foregroundStyle(.orange)
                }
            }
            Section {
                Picker("Style and tone", selection: $draft.style) {
                    ForEach(["Balanced", "Efficient", "Friendly", "Professional"], id: \.self) { Text($0).tag($0) }
                }
                control("Warmth", value: $draft.warmth); control("Enthusiasm", value: $draft.enthusiasm)
                control("Headers and lists", value: $draft.structure); control("Emoji", value: $draft.emoji)
            }
            Section {
                Text("Keep instructions brief to leave room for local conversation context. Preferences apply to future replies. If you enable a remote endpoint, instructions are sent there with your conversation context. They do not grant device permissions or enable unsupported tools.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Behavior").navigationBarTitleDisplayMode(.inline).onAppear { draft = workspace.behavior }
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Save") { do { try workspace.saveBehavior(draft); dismiss() } catch { self.error = error.localizedDescription } }
                    .disabled(draft.instructions.utf8.count > ResponseBehavior.instructionByteLimit || workspace.loadError != nil)
                    .accessibilityIdentifier("behavior.save")
            } }
            .alert("Could not save behavior", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
    private func control(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title).font(.subheadline); Spacer(); Slider(value: value, in: 0...1).frame(maxWidth: 145).accessibilityLabel(title) }
    }
}

struct IntegrationCatalogView: View {
    var broker: PluginBroker?
    var setupError: String?
    @State private var query = ""
    @State private var pluginPresentation: PluginConnectionPresentation?
    @State private var removingPlugin: PluginConnectionRecord?
    @State private var pluginError: String?
    private let groups = ["Email", "Calendar", "Passwords", "Health", "Finances", "Browser", "Location"]
    var body: some View {
        List {
            Section {
                Label(broker?.activeConnection == nil ? "No external integrations connected" : "Reviewed plugin connected", systemImage: "puzzlepiece.extension").font(.headline)
                Text("Connections in the reference recording belong to another app and do not transfer to Orivyn. No account data, credentials or permissions have been copied.").font(.footnote).foregroundStyle(.secondary)
            }
            if let broker {
                PluginConnectionsSection(broker: broker,
                    onAdd: { pluginPresentation = PluginConnectionPresentation() },
                    onConnect: { pluginPresentation = PluginConnectionPresentation(saved: $0) },
                    onRemove: { removingPlugin = $0 })
            }
            else if let setupError { Section { Text(setupError).font(.footnote).foregroundStyle(.red) } }
            if let pluginError { Section { Text(pluginError).font(.footnote).foregroundStyle(.red) } }
            Section("On this iPhone") {
                if query.isEmpty || "Calculator arithmetic offline".localizedCaseInsensitiveContains(query) {
                    NavigationLink { CalculatorView() } label: { Label("Calculator", systemImage: "number") }
                }
                if query.isEmpty || "Shortcuts sharing text".localizedCaseInsensitiveContains(query) {
                    NavigationLink { ShortcutsHelpView() } label: { Label("Shortcuts & sharing", systemImage: "square.and.arrow.up") }
                }
                if query.isEmpty || "Local reminders notifications".localizedCaseInsensitiveContains(query) {
                    NavigationLink { ScheduledRemindersView().navigationTitle("Scheduled") } label: { Label("Local reminders", systemImage: "bell") }
                }
            }
            Section("Native tools and integrations") {
                ForEach(groups.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { title in
                    NavigationLink { IntegrationDetailView(title: title) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: IntegrationDetailView.icon(for: title)).foregroundStyle(IntegrationDetailView.color(for: title)).frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title); Text(IntegrationDetailView.status(for: title)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 5)
                    }
                }
            }
        }.searchable(text: $query, prompt: "Search integrations")
            // A Section distributes presentation modifiers across its rows. Keep
            // one stable presenter on the enclosing List, not one per plugin row.
            .sheet(item: $pluginPresentation) { presentation in
                if let broker { PluginConnectionForm(broker: broker, saved: presentation.saved) }
            }
            .confirmationDialog("Remove this local connection and its saved token?", isPresented: Binding(get: { removingPlugin != nil }, set: { if !$0 { removingPlugin = nil } }), titleVisibility: .visible) {
                Button("Remove connection", role: .destructive) {
                    if let removingPlugin, let broker {
                        do { try broker.removeConnection(id: removingPlugin.id) }
                        catch { pluginError = error.localizedDescription }
                    }
                    removingPlugin = nil
                }
            } message: { Text("This does not delete remote data or revoke the token at its server.") }
    }
}

struct IntegrationDetailView: View {
    let title: String
    static func status(for title: String) -> String {
        switch title {
        case "Email": "Review in Mail"
        case "Calendar": "Review an event"
        case "Browser": "Open a website"
        case "Location": "One-time request"
        default: "Not available in this build"
        }
    }
    static func icon(for title: String) -> String {
        switch title {
        case "Email": "envelope.fill"
        case "Calendar": "calendar"
        case "Passwords": "lock.fill"
        case "Health": "heart.fill"
        case "Finances": "chart.bar.fill"
        case "Browser": "network"
        default: "location.fill"
        }
    }
    static func color(for title: String) -> Color {
        switch title {
        case "Email": .gray
        case "Calendar", "Browser": .blue
        case "Passwords", "Location": .purple
        case "Health": .pink
        default: .green
        }
    }
    private var detail: String {
        switch title {
        case "Email": "Gmail, Outlook and iCloud mail require separate secure account integrations. None is connected. Orivyn can draft text you copy into your mail app."
        case "Calendar": "Calendar access and event-writing are not integrated yet. No calendar permission has been requested and no events are read or changed."
        case "Passwords": "Orivyn does not provide a password vault or browser autofill. Optional model API keys use the existing iOS Keychain service, not chats or project preferences."
        case "Health": "No HealthKit or medical-record integration is included. Orivyn does not read health data or show a connected-health status."
        case "Finances": "No financial accounts are connected. Banking access and financial-data providers require separate integrations and authorization."
        case "Browser": "Web automation, remote browser sessions, cookie management and email-code autofill are not implemented. Orivyn cannot use websites on your behalf from this build."
        default: "Location services are not integrated. Orivyn does not request or collect your location. You can choose to describe a place in a conversation."
        }
    }
    @ViewBuilder var body: some View {
        switch title {
        case "Email": MailDraftView()
        case "Calendar": CalendarDraftView()
        case "Browser": BrowserToolView()
        case "Location": LocationToolView()
        default:
            CapabilityNoticeView(title: title, icon: Self.icon(for: title), detail: detail) { EmptyView() }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct LocalDeviceView: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Section {
                Label("This iPhone", systemImage: "iphone").font(.headline)
                LabeledContent("System", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                LabeledContent("Processing", value: "On device")
            } footer: { Text("Orivyn cannot currently control a Mac, PC or another phone. No device has been paired.") }
            Section("On-device desktop") {
                NavigationLink { VirtualDesktopView(model: model) } label: {
                    Label("Virtual desktop", systemImage: "desktopcomputer")
                }.accessibilityIdentifier("desktop.open")
            }
            Section("External display") {
                NavigationLink { DeskControlView(controller: .shared) } label: {
                    Label("Orivyn Desk", systemImage: "display")
                }.accessibilityIdentifier("desk.open")
            }
            Section("iOS boundaries") {
                Text("Local models run while Orivyn is active. iOS can suspend background work and limits app memory. Signing with SideStore does not remove sandbox, entitlement or background-execution restrictions.").font(.footnote)
            }
        }.navigationTitle("Devices").navigationBarTitleDisplayMode(.inline)
    }
}

private struct CapabilityNoticeView<Actions: View>: View {
    let title: String
    let icon: String
    let detail: String
    let actions: () -> Actions
    init(title: String, icon: String, detail: String, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title; self.icon = icon; self.detail = detail; self.actions = actions
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: icon).font(.title2); Text(title).font(.title3.weight(.semibold))
                    Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Color.evoSurface, in: RoundedRectangle(cornerRadius: 24))
                actions()
            }.padding(20)
        }
    }
}
