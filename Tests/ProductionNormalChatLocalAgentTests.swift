import XCTest
import Foundation
@testable import JarvisEVO

/// Real pinned model decisions + production local dispatcher, synthetic data only.
/// Exercises provider dispatch and a separate real AppModel Automatic Send route.
/// Neither test is physical iPhone UI verification.
@MainActor
final class ProductionNormalChatLocalAgentTests: XCTestCase {
    func testPinnedModelSelectsMemoryReadAndAnswersFromDurableEvidence() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ORIVYN_REQUIRE_NORMAL_CHAT_MODEL"] == "1" else {
            throw XCTSkip("Normal-chat model gate not enabled; no inference pass is claimed.")
        }
        #if !targetEnvironment(simulator)
        XCTFail("Required normal-chat inference gate needs the iOS simulator.")
        #else
        executionTimeAllowance = 750
        guard let path = environment["ORIVYN_CONVERSATION_MODEL_DIR"], path.hasPrefix("/"), path != "/",
              !path.utf8.contains(0) else { XCTFail("Dedicated fixture directory required"); return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { XCTFail("Regular fixture directory required"); return }
        let descriptor = try ProductionModelFixture.descriptor(environment: environment)
        guard descriptor.id == "qwen3-1.7b-q4_k_m" else { XCTFail("Only pinned Q4 fixture admitted"); return }
        let lock = directory.appendingPathComponent(".production-local-agent-test-lock", isDirectory: true)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: lock) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NormalChatModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "Orivyn.NormalChatModel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "remoteEnabled")
        defaults.set(false, forKey: "orivyn.automaticModels")
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("synthetic.sqlite"))
        let model = AppModel(store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: root.appendingPathComponent("NoUserModels")), defaults: defaults)
        let marker = "cedar-" + UUID().uuidString.lowercased()
        let noteID = UUID()
        let saved = await model.saveMemory(id: noteID, content: "Cedar acceptance verification marker: \(marker).")
        XCTAssertTrue(saved)
        let notes = try await store.memories()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.id, noteID)
        XCTAssertEqual(model.memories.first?.id, noteID)
        let goal = "Look through my saved notes for Cedar acceptance and tell me the exact verification marker stored there."
        XCTAssertFalse(goal.contains(marker))
        let turn = try XCTUnwrap(NormalChatLocalTurn(goal: goal, hasAttachments: false, isExternalDraft: false))
        let journal = NormalChatModelJournal(url: root.appendingPathComponent("receipts.txt"))
        let actualModel = LocalAIProvider(store: try LocalModelStore(root: directory), model: descriptor)
        let observedModel = ObservedNormalChatModel(actual: actualModel, journal: journal)
        let provider = NormalChatLocalAgentProvider(turn: turn, model: observedModel,
            validateContext: { try Task.checkCancellation() },
            read: { action in
                try await journal.beforeRead(action)
                return try await LocalReadTools.executeAsync(name: action.name, arguments: action.arguments,
                    model: model, resultByteLimit: 4096)
            }, record: { event in try await journal.record(event) },
            deadline: .now.advanced(by: .seconds(360)))
        var answer = "", streamError: (any Error)?
        do {
            // Deliberately no preloaded memory context or answer in request.
            let request = GenerationRequest(messages: [.init(role: .user, content: goal)], systemPrompt: "")
            for try await token in try await provider.stream(request) {
                try Task.checkCancellation()
                answer += token
                guard answer.utf8.count <= 32_768 else { throw LocalAgentError.outputBound }
            }
            try Task.checkCancellation()
        } catch { streamError = error }
        await actualModel.unload()
        let evidence = await journal.snapshot()
        let disk = (try? String(contentsOf: root.appendingPathComponent("receipts.txt"), encoding: .utf8)) ?? ""
        let attachment = XCTAttachment(string: "scope=one synthetic real-model local-read loop; not UI/device/general autonomy\nmodelSHA256=\(descriptor.sha256)\nerror=\(String(describing: streamError))\nreceipts=\(disk)\nanswer=\(answer)")
        attachment.name = "normal-chat-real-model-read-evidence"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let streamError { throw streamError }
        XCTAssertGreaterThanOrEqual(evidence.requests.count, 2, "Must choose a tool, then answer from recorded evidence")
        XCTAssertLessThanOrEqual(evidence.requests.count, 5)
        XCTAssertFalse(evidence.requests.first?.contains(marker) == true, "Answer must not be preloaded into first inference")
        XCTAssertTrue(evidence.requests.last?.contains(marker) == true, "Final inference must actually receive read evidence")
        let succeeded = evidence.events.filter { $0.phase == .succeeded }
        XCTAssertTrue(succeeded.contains { $0.action.name == "search_memory" && $0.result?.contains(marker) == true })
        XCTAssertTrue(succeeded.contains { $0.result?.contains(noteID.uuidString) == true || $0.result?.contains(noteID.uuidString.lowercased()) == true })
        XCTAssertFalse(succeeded.isEmpty)
        XCTAssertLessThanOrEqual(succeeded.count, 3)
        XCTAssertEqual(evidence.events.filter { $0.phase == .started }.count, succeeded.count)
        XCTAssertFalse(evidence.events.contains { $0.phase == .failed })
        XCTAssertEqual(evidence.reads.count, succeeded.count)
        XCTAssertTrue(disk.contains(marker), "Successful evidence must be persisted, not merely buffered")
        XCTAssertTrue(disk.contains("succeeded"))
        XCTAssertTrue(answer.contains(marker), "Final model answer must use unpredictable returned evidence")
        XCTAssertTrue(answer.contains("Model-generated answer"), "Interpretation must not masquerade as an execution receipt")
        XCTAssertFalse(answer.contains("<think>"))
        XCTAssertFalse(answer.contains("</think>"))

        // A fresh ordinary coding turn must answer directly, not look through memory.
        let codingGoal = "Write one Python print statement that prints 2 + 2."
        let codingJournal = NormalChatModelJournal(url: root.appendingPathComponent("coding-receipts.txt"))
        let codingTurn = try XCTUnwrap(NormalChatLocalTurn(goal: codingGoal, hasAttachments: false, isExternalDraft: false))
        let codingProvider = NormalChatLocalAgentProvider(turn: codingTurn,
            model: ObservedNormalChatModel(actual: actualModel, journal: codingJournal),
            validateContext: { try Task.checkCancellation() },
            read: { action in
                try await codingJournal.beforeRead(action)
                return try await LocalReadTools.executeAsync(name: action.name, arguments: action.arguments,
                    model: model, resultByteLimit: 4096)
            }, record: { event in try await codingJournal.record(event) })
        var codingAnswer = "", codingError: (any Error)?
        do {
            for try await token in try await codingProvider.stream(.init(messages: [.init(role: .user, content: codingGoal)], systemPrompt: "")) {
                try Task.checkCancellation()
                codingAnswer += token
                guard codingAnswer.utf8.count <= 32_768 else { throw LocalAgentError.outputBound }
            }
            try Task.checkCancellation()
        } catch { codingError = error }
        await actualModel.unload()
        let codingEvidence = await codingJournal.snapshot()
        let codingAttachment = XCTAttachment(string: "scope=fresh actual-model coding turn through normal loop\nerror=\(String(describing: codingError))\nreadCount=\(codingEvidence.reads.count)\nanswer=\(codingAnswer)")
        codingAttachment.name = "normal-chat-real-model-code-without-tools"
        codingAttachment.lifetime = .keepAlways
        add(codingAttachment)
        if let codingError { throw codingError }
        XCTAssertEqual(codingEvidence.requests.count, 1, "Code drafting uses plain-text inference without irrelevant tool choice")
        XCTAssertTrue(codingEvidence.reads.isEmpty)
        XCTAssertTrue(codingEvidence.events.isEmpty)
        XCTAssertNotNil(codingAnswer.range(of: #"print\s*\(\s*(?:2\s*\+\s*2|4)\s*\)"#, options: .regularExpression))
        XCTAssertFalse(codingAnswer.contains(marker), "Unrelated prior-turn private evidence must not enter a fresh coding turn")
        XCTAssertFalse(codingAnswer.contains("<think>"))

        // Regression: the owner's generic request, with the preceding incorrect
        // refusal retained. This is a bounded excerpt, not a full transcript replay.
        let genericGoal = "Can you build me a simple python script"
        let refusedHistory: [ChatMessage] = [
            .init(role: .user, content: "Make me an unsigned iOS app"),
            .init(role: .assistant, content: "I’m unable to build or modify executable files or apps outside the Orivyn app. My capabilities are limited to assisting with app-related tasks within the Orivyn environment."),
            .init(role: .user, content: genericGoal)
        ]
        let longHistory: [ChatMessage] = (0..<6).map { index in
            // Synthetic high-entropy excerpts near the wrapper's 512-byte cap.
            let text = (0..<12).map { _ in UUID().uuidString }.joined(separator: " ")
            return ChatMessage(role: index % 2 == 0 ? .user : .assistant, content: text)
        }
        for (label, history) in [("fresh", [ChatMessage(role: .user, content: genericGoal)]),
                                 ("prior-refusal", refusedHistory), ("long-history", longHistory + [.init(role: .user, content: genericGoal)])] {
            let probe = NormalChatLocalAgentProvider(turn: try XCTUnwrap(NormalChatLocalTurn(
                goal: genericGoal, hasAttachments: false, isExternalDraft: false)), model: actualModel,
                validateContext: { try Task.checkCancellation() },
                read: { _ in throw LocalAgentError.invalidState }, record: { _ in
                    XCTFail("Ordinary Python drafting must not start a local read")
                })
            var result = ""
            do {
                for try await token in try await probe.stream(.init(messages: history, systemPrompt: "")) {
                    result += token
                }
            } catch {
                await actualModel.unload()
                throw error
            }
            let evidence = XCTAttachment(string: "scope=generic Python request through production normal loop; bounded supplied refusal excerpt\nmodelSHA256=\(descriptor.sha256)\nvariant=\(label)\nanswer=\(result)")
            evidence.name = "normal-chat-refusal-recovery-" + label
            evidence.lifetime = .keepAlways
            add(evidence)
            for refusal in ["unable to build", "cannot write", "can't write", "limited to assisting with app"] {
                XCTAssertFalse(result.lowercased().contains(refusal))
            }
            XCTAssertNotNil(result.range(of: #"(?s)(?:print\s*\(|def\s+\w+\s*\(|```python)"#, options: .regularExpression),
                "The generic request should receive a usable example, not a refusal")
            XCTAssertFalse(result.contains("<think>"))
            XCTAssertFalse(result.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"), "Ordinary code answer must not be wrapped in unrequested JSON")
        }
        let explainGoal = "Explain"
        let explainHistory: [ChatMessage] = [
            .init(role: .user, content: "Can you make an exact replica of Samsung DeX for iPhone with macOS as the desktop and USB C to HDMI?"),
            .init(role: .assistant, content: "Sorry, I can't assist with that."),
            .init(role: .user, content: "Why not"),
            .init(role: .assistant, content: "I'm not able to assist with that.")]
        let explainProbe = NormalChatLocalAgentProvider(turn: try XCTUnwrap(NormalChatLocalTurn(
            goal: explainGoal, hasAttachments: false, isExternalDraft: false)), model: actualModel,
            validateContext: { try Task.checkCancellation() },
            read: { _ in throw LocalAgentError.invalidState }, record: { _ in XCTFail("Explaining a prior turn needs no local read") })
        var explanation = ""
        for try await token in try await explainProbe.stream(.init(messages: explainHistory + [.init(role: .user, content: explainGoal)], systemPrompt: "")) { explanation += token }
        let explainAttachment = XCTAttachment(string: "scope=exact supplied Explain follow-up after app-building refusals\nanswer=\(explanation)")
        explainAttachment.name = "normal-chat-explain-followup"
        explainAttachment.lifetime = .keepAlways
        add(explainAttachment)
        XCTAssertTrue(["iphone", "ios", "macos"].contains { explanation.lowercased().contains($0) })
        XCTAssertFalse(explanation.lowercased().contains("explain is a verb"))

        // Actual get_app_info dispatch followed by real-tokenizer fitting. A
        // context rejection remains explicit but is not successful answer acceptance.
        let infoGoal = "Read get_app_info now and explain what this app can actually do."
        let infoJournal = NormalChatModelJournal(url: root.appendingPathComponent("info-budget-receipts.txt"))
        let infoProbe = NormalChatLocalAgentProvider(turn: try XCTUnwrap(NormalChatLocalTurn(
            goal: infoGoal, hasAttachments: false, isExternalDraft: false)),
            model: ObservedNormalChatModel(actual: actualModel, journal: infoJournal),
            validateContext: { try Task.checkCancellation() },
            read: { action in
                XCTAssertEqual(action.name, "get_app_info")
                guard action.name == "get_app_info" else { throw LocalAgentError.invalidState }
                try await infoJournal.beforeRead(action)
                return try await LocalReadTools.executeAsync(name: action.name, arguments: action.arguments,
                    model: model, resultByteLimit: 4096)
            }, record: { event in try await infoJournal.record(event) },
            deadline: .now.advanced(by: .seconds(120)))
        var infoAnswer = "", infoError: (any Error)?
        do {
            for try await token in try await infoProbe.stream(.init(
                messages: longHistory + [.init(role: .user, content: infoGoal)], systemPrompt: "")) {
                infoAnswer += token
            }
        } catch { infoError = error }
        await actualModel.unload()
        let infoEvidence = await infoJournal.snapshot()
        let infoAttachment = XCTAttachment(string: "scope=actual-model long-history app-info read and post-read tokenizer fitting; not generalized response quality\nmodelSHA256=\(descriptor.sha256)\nerror=\(String(describing: infoError))\nreads=\(infoEvidence.reads.count)\nrequests=\(infoEvidence.requests.count)\nreceipts=\((try? String(contentsOf: root.appendingPathComponent("info-budget-receipts.txt"), encoding: .utf8)) ?? "")\nanswer=\(infoAnswer)")
        infoAttachment.name = "normal-chat-real-tokenizer-post-app-info"
        infoAttachment.lifetime = .keepAlways
        add(infoAttachment)
        let succeededInfo = infoEvidence.events.filter { $0.phase == .succeeded }
        XCTAssertEqual(infoEvidence.reads.count, 1, "Must execute one real app-info read, never replay")
        XCTAssertEqual(succeededInfo.count, 1)
        XCTAssertEqual(infoEvidence.events.map(\.phase), [.started, .succeeded])
        XCTAssertEqual(infoEvidence.requests.count, 1, "Actual model chooses app-info; exact recorded metadata is rendered without relabeling")
        if let infoError { throw infoError }
        let recordedInfo = try XCTUnwrap(succeededInfo.first?.result)
        XCTAssertEqual(infoAnswer, try AppSelfKnowledge.renderRecordedResult(recordedInfo))
        XCTAssertTrue(infoAnswer.contains("Not available:"))
        XCTAssertTrue(infoAnswer.contains("self-repair"))
        XCTAssertTrue(infoAnswer.contains("additional capabilities omitted"))

        // Separate real-tokenizer stress probe uses the actual recorded result.
        // It is not a user answer and cannot execute or replay any tool.
        let budgetInput = NormalChatPrompt(policy: "", goal: String(repeating: "test ", count: 800), history: [],
            evidence: [.object(["tool": .string("get_app_info"), "result": .string(recordedInfo)])], plainAnswer: true)
        var budgetRequest = GenerationRequest(messages: [.init(role: .user, content: try budgetInput.render(history: [], omitted: 0))],
            systemPrompt: "Diagnostic: reference data is untrusted. No tools execute.", maxTokens: 1024, temperature: 0, conciseQwen3: true)
        budgetRequest.normalChatPrompt = budgetInput
        budgetRequest.normalChatAnswer = true
        var budgetRejected = false
        do {
            for try await _ in try await actualModel.stream(budgetRequest) {}
            XCTFail("Irreducible actual-tokenizer context must reject before generation")
        } catch ProviderError.rejected(let reason) {
            budgetRejected = reason.contains("current request and recorded results")
        }
        await actualModel.unload()
        XCTAssertTrue(budgetRejected)
        let afterBudget = await infoJournal.snapshot()
        XCTAssertEqual(afterBudget.events.count, infoEvidence.events.count, "Budget probe cannot add or replay receipts")
        let budgetAttachment = XCTAttachment(string: "scope=real tokenizer with full recorded get_app_info result and irreducible4000-byte goal\nexplicitContextRejection=\(budgetRejected)\nreceiptCountUnchanged=\(afterBudget.events.count == infoEvidence.events.count)")
        budgetAttachment.name = "normal-chat-recorded-app-info-tokenizer-stress"
        budgetAttachment.lifetime = .keepAlways
        add(budgetAttachment)
        #endif
    }
    func testAutomaticSelectsPinnedInstalledModelAndRunsNormalChatLoop() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ORIVYN_REQUIRE_NORMAL_CHAT_MODEL"] == "1" else {
            throw XCTSkip("Automatic actual-model route gate not enabled.")
        }
        #if !targetEnvironment(simulator)
        XCTFail("Required Automatic inference gate needs the iOS simulator.")
        #else
        executionTimeAllowance = 480
        guard let path = environment["ORIVYN_CONVERSATION_MODEL_DIR"], path.hasPrefix("/"), path != "/",
              !path.utf8.contains(0) else { XCTFail("Dedicated fixture directory required"); return }
        let files = FileManager.default, directory = URL(fileURLWithPath: path, isDirectory: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { XCTFail("Regular fixture directory required"); return }
        let descriptor = try ProductionModelFixture.descriptor(environment: environment)
        guard descriptor.id == "qwen3-1.7b-q4_k_m" else { XCTFail("Only pinned Q4 admitted"); return }
        let lock = directory.appendingPathComponent(".production-local-agent-test-lock", isDirectory: true)
        try files.createDirectory(at: lock, withIntermediateDirectories: false)
        var safeToClean = true
        defer { if safeToClean { try? files.removeItem(at: lock) } }
        let manifest = directory.appendingPathComponent("installed-models.json")
        let original: Data?
        if files.fileExists(atPath: manifest.path) {
            let attributes = try manifest.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { XCTFail("Regular fixture manifest required"); return }
            original = try Data(contentsOf: manifest)
        } else { original = nil }
        defer {
            if safeToClean {
                do {
                    if let original { try original.write(to: manifest, options: .atomic) }
                    else if files.fileExists(atPath: manifest.path) { try files.removeItem(at: manifest) }
                } catch { XCTFail("Could not restore fixture manifest: \(error)") }
            }
        }
        try JSONEncoder().encode([descriptor]).write(to: manifest, options: .atomic)
        let root = files.temporaryDirectory.appendingPathComponent("AutomaticNormalChat-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { if safeToClean { try? files.removeItem(at: root) } }
        let suite = "Orivyn.AutomaticNormalChat.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { if safeToClean { defaults.removePersistentDomain(forName: suite) } }
        defaults.set(true, forKey: "orivyn.automaticModels")
        defaults.set(false, forKey: "remoteEnabled")
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("synthetic.sqlite"))
        let model = AppModel(store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: directory), defaults: defaults)
        // No preparation/factory/decision injection: actual router, verifier and engine.
        let marker = "birch-" + UUID().uuidString.lowercased()
        let saved = await model.saveMemory(content: "Birch acceptance verification marker: \(marker).")
        XCTAssertTrue(saved)
        model.draft = "Look through my saved notes for Birch acceptance and tell me the exact verification marker stored there."
        XCTAssertNil(model.currentDirectLocalReadContract, "The deterministic shortcut must not satisfy this test")
        XCTAssertTrue(model.automaticModelsEnabled)
        XCTAssertTrue(model.automaticLocalChatReadsAvailable)
        XCTAssertTrue(model.canSend)
        safeToClean = false
        model.send()
        let deadline = ContinuousClock.now.advanced(by: .seconds(360))
        while (model.isPreparingAutomaticModel || model.isGenerating) && ContinuousClock.now < deadline && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let finished = !model.isPreparingAutomaticModel && !model.isGenerating && !Task.isCancelled
        if !finished { model.stop() }
        // An unstructured joined cleanup task does not spin on an already-cancelled parent sleep.
        safeToClean = await Task { @MainActor in
            let joinDeadline = ContinuousClock.now.advanced(by: .seconds(90))
            while (model.isPreparingAutomaticModel || model.isGenerating) && ContinuousClock.now < joinDeadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            return !model.isPreparingAutomaticModel && !model.isGenerating
        }.value
        if safeToClean {
            for option in model.providers {
                if let local = option.provider as? LocalAIProvider { await local.unload() }
            }
        }
        let visible = model.activeConversation?.messages.last?.content ?? ""
        let attachment = XCTAttachment(string: "scope=real AppModel Automatic route with single pinned installed model, synthetic memory only\nfinished=\(finished)\njoined=\(safeToClean)\ndecision=\(String(describing: model.automaticDecision))\nerror=\(model.errorMessage ?? "none")\nvisible=\(visible)")
        attachment.name = "automatic-normal-chat-real-model"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(finished, "Actual Automatic route must complete, not time out")
        XCTAssertTrue(safeToClean, "Pending work must join before fixture cleanup")
        guard safeToClean else { return }
        XCTAssertEqual(model.automaticDecision?.model.id, descriptor.id)
        XCTAssertEqual(model.automaticDecision?.needsDownload, false, "Installed fixture must avoid network/model downloads")
        XCTAssertNil(model.errorMessage)
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let persisted = try await store.load(id: conversationID)
        XCTAssertEqual(persisted?.messages.last?.state, .complete)
        XCTAssertEqual(persisted?.messages.last?.content, visible)
        let blocks = visible.components(separatedBy: "[App-recorded local read receipt; display-only, not replayable]\n").dropFirst()
        let receipts = try blocks.map { block -> MCPJSONValue in
            let json = try XCTUnwrap(block.components(separatedBy: "\n[End app-recorded receipt]").first)
            return try MCPJSONValue.parse(Data(json.utf8), maximumBytes: 16_384)
        }
        XCTAssertTrue(receipts.contains { value in
            let object = value.objectValue
            return object?["tool"]?.stringValue == "search_memory" && object?["phase"]?.stringValue == "succeeded"
                && object?["result"]?.stringValue?.contains(marker) == true
        }, "Only a production persisted read receipt proves tool dispatch")
        let answerBoundary = "[Model-generated answer; interpretation is unverified. App-recorded receipts above describe actual local operations.]\n"
        XCTAssertTrue(visible.contains(answerBoundary))
        let finalAnswer = try XCTUnwrap(visible.components(separatedBy: answerBoundary).last)
        XCTAssertTrue(finalAnswer.contains(marker), "Marker in receipt alone is not a grounded model answer")
        XCTAssertFalse(finalAnswer.contains("<think>"))
        #endif
    }

}

/// Observes requests only; never returns or edits a model decision.
private struct ObservedNormalChatModel: AIProvider {
    let actual: LocalAIProvider
    let journal: NormalChatModelJournal
    var id: String { actual.id }
    var displayName: String { actual.displayName }
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        try await journal.beforeModel(request)
        return try await actual.stream(request)
    }
}

private actor NormalChatModelJournal {
    let url: URL
    var events: [NormalChatReadEvent] = []
    var reads: [NormalChatToolAction] = []
    var requests: [String] = []
    var inputs: [NormalChatPrompt] = []
    init(url: URL) { self.url = url }
    func beforeModel(_ request: GenerationRequest) throws {
        if !requests.isEmpty && !(request.normalChatAnswer && events.isEmpty) {
            guard events.last?.phase == .succeeded else { throw LocalAgentError.storage }
            let persisted = try String(contentsOf: url, encoding: .utf8)
            guard persisted.contains(try events.last!.rendered()) else { throw LocalAgentError.storage }
        }
        if let input = request.normalChatPrompt { inputs.append(input) }
        requests.append(request.systemPrompt + request.messages.map(\.content).joined(separator: "\n"))
    }
    func beforeRead(_ action: NormalChatToolAction) throws {
        guard let last = events.last, last.phase == .started, last.action == action else { throw LocalAgentError.storage }
        let persisted = try String(contentsOf: url, encoding: .utf8)
        guard persisted.contains(try last.rendered()) else { throw LocalAgentError.storage }
        reads.append(action)
    }
    func record(_ event: NormalChatReadEvent) throws {
        if event.phase != .started {
            guard let previous = events.last, previous.phase == .started,
                  previous.operationID == event.operationID, previous.action == event.action else { throw LocalAgentError.storage }
        }
        let next = events + [event]
        let data = Data(try next.map { try $0.rendered() }.joined().utf8)
        try data.write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
        events = next
    }
    func snapshot() -> (events: [NormalChatReadEvent], reads: [NormalChatToolAction], requests: [String], inputs: [NormalChatPrompt]) {
        (events, reads, requests, inputs)
    }
}
