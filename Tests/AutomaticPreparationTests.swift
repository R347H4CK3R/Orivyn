import XCTest
@testable import JarvisEVO

@MainActor
final class AutomaticPreparationTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "OrivynAutoTests.\(UUID().uuidString)"; defaults = UserDefaults(suiteName: suite)
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func testPreparationDoesNotClearDraftOrCreateHistoryBeforeProviderReady() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Explain a sunset"; model.send()
        try await waitFor { prep.count == 1 }
        XCTAssertTrue(model.isPreparingAutomaticModel); XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(model.draft, "Explain a sunset"); XCTAssertTrue(model.conversations.isEmpty)
        prep.complete(0)
        try await waitFor { !model.isPreparingAutomaticModel && !model.isGenerating }
        let calls = await source.count; XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.activeConversation?.messages.first?.content, "Explain a sunset")
        XCTAssertEqual(model.selectedProviderID, "manual-test", "Automatic selection must not overwrite the manual choice.")
    }

    func testRepeatedSendDuringPreparationDoesNotStartAnotherOperation() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Hello"; model.send(); model.send()
        try await waitFor { prep.count == 1 }; XCTAssertFalse(model.canSend)
        prep.complete(0); try await waitFor { !model.isPreparingAutomaticModel && !model.isGenerating }
        let calls = await source.count; XCTAssertEqual(calls, 1)
    }

    func testEditAndRevertPermanentlyInvalidatesPreparation() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Original"; model.send(); try await waitFor { prep.count == 1 }
        model.draft = "Changed"; model.draft = "Original"
        prep.complete(0); try await settle()
        XCTAssertFalse(model.isPreparingAutomaticModel); XCTAssertEqual(model.draft, "Original")
        XCTAssertTrue(model.conversations.isEmpty); let calls = await source.count; XCTAssertEqual(calls, 0)
    }

    func testAttachmentChangeInvalidatesAndKeepsTheNewAttachment() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Explain"; model.send(); try await waitFor { prep.count == 1 }
        let file = root.appendingPathComponent("new.txt"); try Data("New attachment".utf8).write(to: file)
        let attachment = try model.attachmentService.importFile(at: file)
        model.pendingAttachments = [attachment]
        prep.complete(0); try await settle()
        XCTAssertEqual(model.pendingAttachments, [attachment]); XCTAssertEqual(model.draft, "Explain")
        XCTAssertTrue(model.conversations.isEmpty); let calls = await source.count; XCTAssertEqual(calls, 0)
    }

    func testConversationSwitchCannotSubmitPreparedTextIntoAnotherConversation() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Original"; model.send(); try await waitFor { prep.count == 1 }
        let other = UUID(); model.selectedConversationID = other
        prep.complete(0); try await settle()
        XCTAssertEqual(model.selectedConversationID, other); XCTAssertEqual(model.draft, "Original")
        XCTAssertTrue(model.conversations.isEmpty); let calls = await source.count; XCTAssertEqual(calls, 0)
    }

    func testManualProviderChangeCancelsWithoutBeingOverwritten() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Original"; model.send(); try await waitFor { prep.count == 1 }
        model.selectedProviderID = LocalModelCatalog.defaultModel.id
        prep.complete(0); try await settle()
        XCTAssertEqual(model.selectedProviderID, LocalModelCatalog.defaultModel.id)
        XCTAssertEqual(model.draft, "Original"); let calls = await source.count; XCTAssertEqual(calls, 0)
    }

    func testTurningAutomaticModeOffCancelsInFlightPreparation() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Hello"; model.send(); try await waitFor { prep.count == 1 }
        model.automaticModelsEnabled = false
        prep.complete(0); try await settle()
        XCTAssertFalse(model.isPreparingAutomaticModel); XCTAssertEqual(model.draft, "Hello")
        let calls = await source.count; XCTAssertEqual(calls, 0)
    }

    func testNetworkConsentChangeInvalidatesThePreviousRequest() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Hello"; model.send(); try await waitFor { prep.count == 1 }
        XCTAssertEqual(prep.cellularChoices, [false])
        model.automaticAllowsCellular = true
        prep.complete(0); try await settle()
        XCTAssertEqual(model.draft, "Hello"); let calls = await source.count; XCTAssertEqual(calls, 0)
    }

    func testExplicitCancelPreservesDraftAndRejectsLateCompletion() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Keep"; model.send(); try await waitFor { prep.count == 1 }
        model.cancelAutomaticPreparation(); prep.complete(0); try await settle()
        XCTAssertEqual(model.draft, "Keep"); XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertFalse(model.isPreparingAutomaticModel); let calls = await source.count; XCTAssertEqual(calls, 0)
    }

    func testStopAlsoCancelsPreparationWithoutStartingGeneration() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Keep"; model.send(); try await waitFor { prep.count == 1 }
        model.stop(); prep.complete(0); try await settle()
        XCTAssertEqual(model.draft, "Keep"); XCTAssertFalse(model.isPreparingAutomaticModel)
        let calls = await source.count; XCTAssertEqual(calls, 0)
    }

    func testPreparationIntegrityFailureDoesNotCreateHistoryOrDeleteDraft() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Keep"; model.send(); try await waitFor { prep.count == 1 }
        prep.complete(0, error: LocalModelError.integrityMismatch)
        try await waitFor { !model.isPreparingAutomaticModel }
        XCTAssertNotNil(model.errorMessage); XCTAssertEqual(model.draft, "Keep")
        XCTAssertTrue(model.conversations.isEmpty); let calls = await source.count; XCTAssertEqual(calls, 0)
    }

    func testOldCompletionCannotFinishOrClearNewPreparation() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "First"; model.send(); try await waitFor { prep.count == 1 }
        model.cancelAutomaticPreparation(); model.draft = "Second"; model.send()
        try await waitFor { prep.count == 2 }
        prep.progress(1, fraction: 0.4); prep.progress(0, fraction: 0.9)
        XCTAssertEqual(model.downloadProgress, 0.4)
        prep.complete(0); try await settle()
        XCTAssertTrue(model.isPreparingAutomaticModel); XCTAssertEqual(model.draft, "Second")
        prep.complete(1); try await waitFor { !model.isPreparingAutomaticModel && !model.isGenerating }
        let calls = await source.count; XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.activeConversation?.messages.first?.content, "Second")
    }

    func testManualDownloadIsNotPiggybackedOrCanceledByAutomaticSend() async throws {
        let (model, prep, source) = try fixture()
        model.beginControlledModelDownloadFixture()
        model.draft = "Keep"; model.send(); try await settle()
        XCTAssertEqual(prep.count, 0); XCTAssertNotNil(model.downloadingModelID)
        XCTAssertEqual(model.draft, "Keep"); let calls = await source.count; XCTAssertEqual(calls, 0)
        model.cancelDownload()
        try await waitFor { model.downloadingModelID == nil }
    }

    func testDisallowedNetworkTransitionCancelsOnlyOwnedAutomaticDownload() async throws {
        let (model, prep, source) = try fixture()
        model.automaticAllowsCellular = true
        model.draft = "Keep"; model.send(); try await waitFor { prep.count == 1 }
        prep.progress(0, fraction: 0.2)
        model.automaticNetworkChanged(to: .constrained)
        XCTAssertFalse(model.isPreparingAutomaticModel); XCTAssertNil(model.downloadingModelID)
        prep.complete(0); try await settle()
        XCTAssertEqual(model.draft, "Keep"); XCTAssertTrue(model.conversations.isEmpty)
        let calls = await source.count; XCTAssertEqual(calls, 0)
        model.beginControlledModelDownloadFixture()
        model.automaticNetworkChanged(to: .offline)
        XCTAssertNotNil(model.downloadingModelID, "Automatic policy must not cancel a manual download.")
        model.cancelDownload(); try await waitFor { model.downloadingModelID == nil }
    }

    func testNetworkTransitionDoesNotCancelInstalledModelPreparation() async throws {
        let (model, prep, source) = try fixture()
        model.draft = "Offline answer"; model.send(); try await waitFor { prep.count == 1 }
        model.automaticNetworkChanged(to: .offline)
        XCTAssertTrue(model.isPreparingAutomaticModel)
        prep.complete(0); try await waitFor { !model.isPreparingAutomaticModel && !model.isGenerating }
        let calls = await source.count; XCTAssertEqual(calls, 1)
    }

    private func fixture() throws -> (AppModel, ControlledAutomaticPreparer, AutoReplySource) {
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("test.sqlite"))
        let attachments = try AttachmentService(directory: root.appendingPathComponent("Attachments"))
        let models = try LocalModelStore(root: root.appendingPathComponent("Models"))
        let prep = ControlledAutomaticPreparer(), source = AutoReplySource()
        let model = AppModel(store: store, attachmentService: attachments, modelStore: models, defaults: defaults, automaticPreparer: prep, automaticProviderFactory: { AutoReplyProvider(id: $0.id, source: source) })
        model.replaceProviders([
            ProviderOption(id: "manual-test", title: "Manual", detail: "Test only", provider: AutoReplyProvider(id: "manual-test", source: source)),
            ProviderOption(id: LocalModelCatalog.defaultModel.id, title: "Automatic", detail: "Test only", provider: AutoReplyProvider(id: LocalModelCatalog.defaultModel.id, source: source))
        ])
        model.automaticModelsEnabled = true
        return (model, prep, source)
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { XCTFail("Timed out"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private func settle() async throws { for _ in 0..<5 { await Task.yield() }; try await Task.sleep(for: .milliseconds(20)) }
}

@MainActor
private final class ControlledAutomaticPreparer: AutomaticModelPreparing {
    private var continuations: [CheckedContinuation<AutomaticModelDecision, any Error>] = []
    private var callbacks: [@MainActor (AutomaticModelDecision, Double?) -> Void] = []
    private(set) var cellularChoices: [Bool] = []
    var count: Int { continuations.count }
    private var decision: AutomaticModelDecision { AutomaticModelDecision(model: LocalModelCatalog.defaultModel, needsDownload: true, reason: "Controlled preparation boundary", purpose: "General chat") }
    func prepare(text: String, allowsCellular: Bool, onProgress: @escaping @MainActor (AutomaticModelDecision, Double?) -> Void) async throws -> AutomaticModelDecision {
        cellularChoices.append(allowsCellular); callbacks.append(onProgress)
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func progress(_ index: Int, fraction: Double) { callbacks[index](decision, fraction) }
    func complete(_ index: Int, error: (any Error)? = nil) {
        if let error { continuations[index].resume(throwing: error) }
        else { continuations[index].resume(returning: decision) }
    }
}
private struct AutoReplyProvider: AIProvider {
    let id: String
    let displayName = "Controlled automatic provider"
    let source: AutoReplySource
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> { await source.respond() }
}
private actor AutoReplySource {
    private(set) var count = 0
    func respond() -> AsyncThrowingStream<String, Error> {
        count += 1
        return AsyncThrowingStream { continuation in continuation.yield("Test response"); continuation.finish() }
    }
}
