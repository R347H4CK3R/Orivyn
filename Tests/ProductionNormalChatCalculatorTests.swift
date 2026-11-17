import XCTest
import Foundation
@testable import JarvisEVO

/// No scripted decisions or retries. Real model, real bound arithmetic and durable receipts.
@MainActor
final class ProductionNormalChatCalculatorTests: XCTestCase {
    func testPinnedModelChoosesCalculatorAndAnswersFromVerifiedResult() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ORIVYN_REQUIRE_NORMAL_CHAT_MODEL"] == "1" else {
            throw XCTSkip("Normal-chat model gate not enabled; no inference pass is claimed.")
        }
        #if !targetEnvironment(simulator)
        XCTFail("Required normal-chat inference gate needs the iOS simulator.")
        #else
        executionTimeAllowance = 300
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NormalChatCalculator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "Orivyn.NormalChatCalculator.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "remoteEnabled")
        defaults.set(false, forKey: "orivyn.automaticModels")
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("synthetic.sqlite"))
        let model = AppModel(store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: root.appendingPathComponent("NoUserModels")), defaults: defaults)
        let goal = "Calculate 173 * 29 - 41"
        let turn = try XCTUnwrap(NormalChatLocalTurn(goal: goal, hasAttachments: false, isExternalDraft: false))
        let journal = CalculatorModelJournal(url: root.appendingPathComponent("receipts.txt"))
        let actualModel = LocalAIProvider(store: try LocalModelStore(root: directory), model: descriptor)
        let provider = NormalChatLocalAgentProvider(turn: turn,
            model: ObservedCalculatorModel(actual: actualModel, journal: journal),
            validateContext: { try Task.checkCancellation() },
            read: { action in
                try await journal.beforeRead(action)
                return try await LocalReadTools.executeAsync(name: action.name, arguments: action.arguments,
                    model: model, resultByteLimit: 4096, trustedGoal: goal)
            }, record: { event in try await journal.record(event) })
        var answer = "", streamError: (any Error)?
        do {
            for try await token in try await provider.stream(.init(messages: [.init(role: .user, content: goal)], systemPrompt: "")) {
                try Task.checkCancellation()
                answer += token
                guard answer.utf8.count <= 32_768 else { throw LocalAgentError.outputBound }
            }
            try Task.checkCancellation()
        } catch { streamError = error }
        await actualModel.unload()
        let evidence = await journal.snapshot()
        let disk = (try? String(contentsOf: root.appendingPathComponent("receipts.txt"), encoding: .utf8)) ?? ""
        let attachment = XCTAttachment(string: "scope=actual pinned model chooses arithmetic; production parser/dispatcher; synthetic input; not UI/device proof\nmodelSHA256=\(descriptor.sha256)\nerror=\(String(describing: streamError))\nreceipts=\(disk)\nanswer=\(answer)")
        attachment.name = "normal-chat-real-model-calculator"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let streamError { throw streamError }
        XCTAssertEqual(evidence.requests.count, 2, "Model must choose the tool then answer from its recorded result")
        XCTAssertFalse(evidence.requests.first?.contains("4976") == true, "Result must not be injected before tool execution")
        XCTAssertTrue(evidence.requests.last?.contains("4976") == true)
        XCTAssertEqual(evidence.reads.count, 1)
        let succeeded = evidence.events.filter { $0.phase == .succeeded }
        XCTAssertEqual(succeeded.count, 1)
        XCTAssertEqual(evidence.events.filter { $0.phase == .started }.count, 1)
        XCTAssertFalse(evidence.events.contains { $0.phase == .failed })
        let event = try XCTUnwrap(succeeded.first)
        XCTAssertEqual(event.action.name, "calculate")
        let result = try XCTUnwrap(event.result)
        let verified = try XCTUnwrap(LocalCalculationEvidence.validated(goal: goal,
            arguments: event.action.arguments, result: result))
        XCTAssertEqual(verified.result, "4976", "Independent fixed arithmetic oracle")
        XCTAssertTrue(disk.contains(try event.rendered()), "Succeeded evidence must be durable")
        XCTAssertTrue(answer.hasPrefix("\n[Model-generated answer; interpretation is unverified. App-recorded receipts above describe actual local operations.]\n"))
        XCTAssertNotNil(answer.range(of: #"(?<![0-9])4,?976(?![0-9])"#, options: .regularExpression))
        XCTAssertFalse(answer.contains("<think>"))
        XCTAssertFalse(answer.contains("</think>"))
        #endif
    }
}

/// Observes requests only; never returns or edits a model decision.
private struct ObservedCalculatorModel: AIProvider {
    let actual: LocalAIProvider
    let journal: CalculatorModelJournal
    var id: String { actual.id }
    var displayName: String { actual.displayName }
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> {
        try await journal.beforeModel(request)
        return try await actual.stream(request)
    }
}

private actor CalculatorModelJournal {
    let url: URL
    var events: [NormalChatReadEvent] = []
    var reads: [NormalChatToolAction] = []
    var requests: [String] = []
    init(url: URL) { self.url = url }
    func beforeModel(_ request: GenerationRequest) throws {
        if !requests.isEmpty {
            guard events.last?.phase == .succeeded else { throw LocalAgentError.storage }
            let persisted = try String(contentsOf: url, encoding: .utf8)
            guard persisted.contains(try events.last!.rendered()) else { throw LocalAgentError.storage }
        }
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
    func snapshot() -> (events: [NormalChatReadEvent], reads: [NormalChatToolAction], requests: [String]) {
        (events, reads, requests)
    }
}
