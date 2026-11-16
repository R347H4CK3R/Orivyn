#if DEBUG
import SwiftUI
import Observation

/// Explicitly labeled native touch/drag fixtures. This entire file is excluded
/// from Release. It never participates in the required real-model test gate.
@MainActor
struct RootViewRegressionFixtureHost: View {
    let mode: String
    @State private var fixture: RootViewRegressionFixture?
    @State private var failure: String?

    static var requestedMode: String? { resolveMode(arguments: ProcessInfo.processInfo.arguments) }

    static func resolveMode(arguments: [String]) -> String? {
        guard arguments.contains("--uitesting"),
              let index = arguments.firstIndex(of: "--root-view-fixture"),
              arguments.indices.contains(index + 1),
              ["voice-ownership", "history-scroll", "model-download", "unavailable-provider", "chat-local-tasks"].contains(arguments[index + 1]) else { return nil }
        return arguments[index + 1]
    }

    var body: some View {
        Group {
            if let fixture {
                VStack(spacing: 4) {
                    Text("CONTROLLED ROOTVIEW FIXTURE · NOT MODEL OUTPUT")
                        .font(.caption2.bold()).accessibilityIdentifier("fixture.notice")
                    if mode == "model-download" {
                        ModelManagerView(model: fixture.model)
                    } else if mode == "unavailable-provider" {
                        RootView(model: fixture.model)
                    } else if mode == "chat-local-tasks" {
                        Text("SYNTHETIC TASK RECORDS · NO LOCAL MODEL · NO TOOL EXECUTION")
                            .font(.caption2).accessibilityIdentifier("fixture.chatTasks.notice")
                        HStack {
                            Button("Origin chat A") { fixture.model.selectConversation(fixture.historyA) }.accessibilityIdentifier("fixture.history.a")
                            Button("Other chat B") { fixture.model.selectConversation(fixture.historyB) }.accessibilityIdentifier("fixture.history.b")
                        }.font(.caption)
                        RootView(model: fixture.model)
                    } else if mode == "voice-ownership" {
                        HStack {
                            Button("Permission") { fixture.prepareVoice("permission") }.accessibilityIdentifier("fixture.voice.permission")
                            Button("Listen") { fixture.prepareVoice("listening") }.accessibilityIdentifier("fixture.voice.listening")
                            Button("Finalize") { fixture.prepareVoice("finishing") }.accessibilityIdentifier("fixture.voice.finishing")
                            Button("Stop") { fixture.session.stop() }.accessibilityIdentifier("fixture.voice.stop")
                        }.font(.caption)
                        Text(fixture.voiceState).font(.caption2).accessibilityIdentifier("fixture.state.\(fixture.voiceState)")
                        RootView(model: fixture.model, fixtureVoiceSession: fixture.session)
                    } else {
                        HStack {
                            Button("History A") { fixture.model.selectConversation(fixture.historyA) }.accessibilityIdentifier("fixture.history.a")
                            Button("History B") { fixture.model.selectConversation(fixture.historyB) }.accessibilityIdentifier("fixture.history.b")
                            Button("Short") { fixture.model.selectConversation(fixture.shortHistory) }.accessibilityIdentifier("fixture.history.short")
                        }.font(.caption)
                        HStack {
                            Button("Begin controlled stream") { fixture.beginStream() }.accessibilityIdentifier("fixture.stream.begin")
                            Button("Append controlled text") { fixture.appendStream() }.accessibilityIdentifier("fixture.stream.append")
                        }.font(.caption)
                        Text(fixture.streamState).font(.caption2).accessibilityIdentifier("fixture.stream.\(fixture.streamState)")
                        RootView(model: fixture.model)
                    }
                }
            } else if let failure { Text("Fixture setup failed: \(failure)") }
            else { ProgressView("Preparing controlled RootView fixture…") }
        }
        .task {
            guard fixture == nil else { return }
            do { fixture = try await RootViewRegressionFixture.make(mode: mode) }
            catch { failure = error.localizedDescription }
        }
        .onDisappear { fixture?.stop() }
    }
}

@MainActor @Observable
private final class RootViewRegressionFixture {
    let model: AppModel
    let session: VoiceConversationSession
    let historyA: UUID
    let historyB: UUID
    let shortHistory: UUID
    var streamState = "idle"
    private let audio: RootViewFixtureAudio
    private let tokens: RootViewFixtureTokens
    private var work: Task<Void, Never>?

    private init(model: AppModel, audio: RootViewFixtureAudio, tokens: RootViewFixtureTokens, histories: [UUID]) {
        self.model = model
        self.audio = audio
        self.tokens = tokens
        session = VoiceConversationSession(model: model, audio: audio)
        historyA = histories[0]; historyB = histories[1]; shortHistory = histories[2]
    }

    static func make(mode: String) async throws -> RootViewRegressionFixture {
        // Unique temporary storage/defaults can never overlap normal or real-inference UI data.
        let identifier = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("JarvisEVORootFixture-" + identifier)
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("fixture.sqlite"))
        let attachments = try AttachmentService(directory: root.appendingPathComponent("Attachments"))
        let models = try LocalModelStore(root: root.appendingPathComponent("Models"))
        let defaults = UserDefaults(suiteName: "JarvisEVO.RootFixture." + identifier)!
        let a = history("A", rows: mode == "chat-local-tasks" ? 1 : 24, updated: Date(timeIntervalSince1970: 3))
        let b = history("B", rows: 12, updated: Date(timeIntervalSince1970: 2))
        let short = Conversation(title: "Controlled short fixture", updatedAt: Date(timeIntervalSince1970: 1),
                                 messages: [ChatMessage(role: .assistant, content: "FIXTURE SHORT TRANSCRIPT")])
        if mode == "history-scroll" || mode == "chat-local-tasks" { for conversation in [a, b, short] { try await store.save(conversation) } }
        let model = AppModel(store: store, attachmentService: attachments, modelStore: models, defaults: defaults)
        await model.bootstrap()
        if mode == "model-download" { model.beginControlledModelDownloadFixture() }
        let tokens = RootViewFixtureTokens()
        if mode == "unavailable-provider" {
            model.automaticModelsEnabled = false
            model.replaceProviders([ProviderOption(id: "fixture-unavailable", title: "Unavailable provider fixture", detail: "No inference or audio permission is expected", provider: nil)])
        } else {
            model.replaceProviders([ProviderOption(id: "root-ui-fixture", title: "Controlled UI fixture", detail: "Not an AI model", provider: RootViewFixtureProvider(tokens: tokens))])
        }
        if mode == "history-scroll" || mode == "chat-local-tasks" { model.selectConversation(a.id) }
        if mode == "chat-local-tasks" {
            model.configureLocalWork(directory: root)
            guard let directory = model.localAgentDirectory else { throw LocalAgentError.unavailable }
            try seedChatTasks(directory: directory, origin: a.id)
            model.draft = "Keep this synthetic draft"
        }
        return RootViewRegressionFixture(model: model, audio: RootViewFixtureAudio(), tokens: tokens, histories: [a.id, b.id, short.id])
    }

    /// Synthetic records travel through the production reducer and atomic store.
    /// No task runner, inference provider or native tool is invoked by setup.
    private static func seedChatTasks(directory: URL, origin: UUID) throws {
        let core = try LocalAgentCore(), store = try LocalAgentStore(directory: directory)
        for (id, goal, completed) in [
            ("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01", "Synthetic answered task", true),
            ("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02", "Synthetic interrupted task", false)
        ] {
            let request: MCPJSONValue = .object(["id": .string(id), "goal": .string(goal),
                "contract": .object(["schema": .integer(1), "steps": .array([
                    .object(["name": .string("get_app_info"), "arguments": .object([:])])])])])
            let input = String(decoding: try request.encoded(maximumBytes: 4096), as: UTF8.self)
            var state = try core.call("createContract", [input])
            state = try core.call("acceptDecision", [state, #"{"type":"tool","name":"get_app_info","arguments":{}}"#])
            if completed {
                let operation = try core.snapshot(state).pending
                guard let operation else { throw LocalAgentError.invalidState }
                let evidence: MCPJSONValue = .object(["app": .string("SYNTHETIC LOCAL EVIDENCE - NO TOOL EXECUTED"),
                    "assistant": .string("Fixture"), "repository": .string(""), "repositoryAccess": .string("none"), "capabilities": .array([])])
                let result: MCPJSONValue = .object(["operationID": .string(operation.operationID),
                    "result": .string(String(decoding: try evidence.encoded(maximumBytes: 4096), as: UTF8.self))])
                state = try core.call("recordResult", [state, String(decoding: try result.encoded(maximumBytes: 4096), as: UTF8.self)])
                state = try core.call("acceptDecision", [state, #"{"type":"answer","text":"SYNTHETIC MODEL ANSWER - NOT INFERENCE"}"#])
            } else { state = try core.call("recover", [state]) }
            try store.bindOrigin(id: id, conversationID: origin)
            try store.save(state, id: id)
        }
    }

    private static func history(_ name: String, rows: Int, updated: Date) -> Conversation {
        var messages = (1...rows).map { index in
            ChatMessage(role: .assistant, content: String(format: "FIXTURE %@ ROW %02d", name, index)
                + "\n\nControlled history text for native scrolling. This is not an assistant answer. Each row has deliberately repeatable height and a unique visible marker.")
        }
        messages.append(ChatMessage(role: .assistant, content: "FIXTURE \(name) LAST"))
        return Conversation(title: "Controlled history \(name)", updatedAt: updated, messages: messages)
    }

    var voiceState: String {
        switch session.controller.state {
        case .requestingPermission: "permission"
        case .listening: "listening"
        case .finishing: "finishing"
        default: "stopped"
        }
    }

    func prepareVoice(_ phase: String) {
        work?.cancel()
        session.stop()
        audio.holdsPermission = phase == "permission"
        model.draft = "Audio-owned draft"
        do { try session.start() }
        catch { model.report(error); return }
        if phase == "finishing" {
            work = Task { @MainActor in
                let deadline = ContinuousClock.now + .seconds(5)
                while session.controller.state == .requestingPermission && ContinuousClock.now < deadline {
                    do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
                }
                guard !Task.isCancelled else { return }
                session.controller.finishTurn()
            }
        }
    }

    func beginStream() {
        guard !model.isGenerating else { return }
        model.draft = "Controlled stream request, not inference"
        model.send()
        work = Task { @MainActor in
            let deadline = ContinuousClock.now + .seconds(5)
            while await tokens.subscriptions == 0 && ContinuousClock.now < deadline {
                do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
            }
            guard !Task.isCancelled, await tokens.subscriptions > 0 else { streamState = "failed"; return }
            await tokens.emit("Controlled streamed view fixture.")
            streamState = "waiting"
        }
    }

    func appendStream() {
        guard streamState == "waiting", model.isGenerating else { return }
        work = Task { @MainActor in
            await tokens.emit("\n\n" + String(repeating: "More controlled content to grow the same transcript.\n\n", count: 20) + "FIXTURE STREAM TAIL")
            await tokens.finish()
            let deadline = ContinuousClock.now + .seconds(5)
            while model.isGenerating && ContinuousClock.now < deadline {
                do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
            }
            guard !Task.isCancelled, !model.isGenerating,
                  model.activeConversation?.messages.last?.content.hasSuffix("FIXTURE STREAM TAIL") == true else { streamState = "failed"; return }
            streamState = "appended"
        }
    }

    func stop() { work?.cancel(); session.stop(); model.stop(); model.cancelDownload() }
}

private struct RootViewFixtureProvider: AIProvider {
    let id = "root-ui-fixture"
    let displayName = "Controlled UI fixture, not inference"
    let tokens: RootViewFixtureTokens
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> { await tokens.subscribe() }
}
private actor RootViewFixtureTokens {
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private(set) var subscriptions = 0
    func subscribe() -> AsyncThrowingStream<String, Error> {
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        continuation = pair.continuation; subscriptions += 1
        return pair.stream
    }
    func emit(_ text: String) { continuation?.yield(text) }
    func finish() { continuation?.finish() }
}

@MainActor private final class RootViewFixtureAudio: VoiceConversationAudio {
    var isRecording = false
    var isFinishing = false
    var onTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?
    var onFinishing: (() -> Void)?
    var onError: ((String) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onPlaybackCancelled: (() -> Void)?
    var onInterruption: (() -> Void)?
    var holdsPermission = false
    private var attempt: UUID?
    private var permission: CheckedContinuation<Void, Never>?
    func startRecording() async throws {
        let id = UUID(); attempt = id
        if holdsPermission { await withCheckedContinuation { permission = $0 } }
        guard !Task.isCancelled, attempt == id else { return }
        isRecording = true
    }
    func finishRecording() { isRecording = false; isFinishing = true; onFinishing?() }
    func stopRecording() {
        attempt = nil; isRecording = false; isFinishing = false
        let pending = permission; permission = nil; pending?.resume()
    }
    func speak(_ text: String) throws { }
    func stopSpeaking() { }
}
#endif
