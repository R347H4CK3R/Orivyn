import XCTest
@testable import JarvisEVO

@MainActor
final class LocalHeavyWorkTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "Orivyn.HeavyWorkTests.\(UUID().uuidString)"; defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root)
    }
    func testPreparationReservesBeforeAwaitAndKeepsComposerUnchanged() async throws {
        let (model, release, _) = try fixture()
        model.draft = "Keep"; let provider = model.selectedProviderID
        let file = root.appendingPathComponent("note.txt"); try Data("notes".utf8).write(to: file)
        let attachment = try model.attachmentService.importFile(at: file); model.pendingAttachments = [attachment]
        let id = UUID(); let task = Task { try await model.beginHeavyWork(id: id, kind: .imageCreation) }
        try await waitFor { await release.count == 1 }
        XCTAssertEqual(model.heavyWorkLease?.phase, .preparing); XCTAssertFalse(model.canSend)
        XCTAssertEqual(model.heavyWorkLease?.id, id)
        await release.finish(0); try await task.value
        XCTAssertEqual(model.heavyWorkLease?.phase, .ready)
        XCTAssertEqual(model.draft, "Keep"); XCTAssertEqual(model.pendingAttachments, [attachment])
        XCTAssertEqual(model.selectedProviderID, provider); XCTAssertTrue(model.conversations.isEmpty)
        model.endHeavyWork(id: id); XCTAssertNil(model.heavyWorkLease); XCTAssertTrue(model.canSend)
    }
    func testConcurrentLeaseIsRefusedWithoutSecondRelease() async throws {
        let (model, release, _) = try fixture(); let id = UUID()
        let task = Task { try await model.beginHeavyWork(id: id, kind: .imageCreation) }
        try await waitFor { await release.count == 1 }
        do { try await model.beginHeavyWork(id: UUID(), kind: .vision); XCTFail("Concurrent admission") }
        catch { XCTAssertEqual(error as? LocalHeavyWorkError, .busy) }
        let count = await release.count; XCTAssertEqual(count, 1)
        await release.finish(0); try await task.value; model.endHeavyWork(id: id)
    }
    func testDismissedPendingLeaseCannotStartOrAdmitAnotherUntilActualRelease() async throws {
        let (model, release, _) = try fixture(); let id = UUID()
        let task = Task { try await model.beginHeavyWork(id: id, kind: .imageCreation) }
        try await waitFor { await release.count == 1 }
        model.endHeavyWork(id: id)
        XCTAssertEqual(model.heavyWorkLease?.phase, .revoked)
        do { try await model.beginHeavyWork(id: UUID(), kind: .virtualDesktop); XCTFail("Admitted during release") } catch {}
        await release.finish(0)
        do { try await task.value; XCTFail("Dismissed lease became ready") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(model.heavyWorkLease)
        let next = UUID(); let newer = Task { try await model.beginHeavyWork(id: next, kind: .imageCreation) }
        try await waitFor { await release.count == 2 }; await release.finish(1); try await newer.value
        model.endHeavyWork(id: id)
        XCTAssertEqual(model.heavyWorkLease?.id, next, "Stale dismissal cannot release a newer owner")
        model.endHeavyWork(id: next)
    }
    func testBackgroundRevokesButDoesNotReleasePresentedLeaseUntilDismissal() async throws {
        let (model, release, _) = try fixture(); let id = UUID()
        let task = Task { try await model.beginHeavyWork(id: id, kind: .imageCreation) }
        try await waitFor { await release.count == 1 }; await release.finish(0); try await task.value
        model.draft = "Keep"; model.setHeavyWorkForeground(false)
        XCTAssertEqual(model.heavyWorkLease?.phase, .revoked); XCTAssertFalse(model.canSend)
        model.setHeavyWorkForeground(true)
        XCTAssertEqual(model.heavyWorkLease?.phase, .revoked, "Foreground must never restore consent")
        model.endHeavyWork(id: id); XCTAssertTrue(model.canSend)
    }
    func testBackgroundDuringReleaseNeverGrantsReady() async throws {
        let (model, release, _) = try fixture(); let id = UUID()
        let task = Task { try await model.beginHeavyWork(id: id, kind: .imageCreation) }
        try await waitFor { await release.count == 1 }; model.setHeavyWorkForeground(false)
        await release.finish(0)
        do { try await task.value; XCTFail("Background admission") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(model.heavyWorkLease?.phase, .revoked); model.endHeavyWork(id: id)
        do { try await model.beginHeavyWork(id: UUID(), kind: .imageCreation); XCTFail("Background admission") }
        catch { XCTAssertEqual(error as? LocalHeavyWorkError, .background) }
    }
    func testPreCanceledAcquisitionDoesNotReleaseOrReserve() async throws {
        let (model, release, _) = try fixture()
        let task = Task { try await model.beginHeavyWork(id: UUID(), kind: .imageCreation) }
        task.cancel()
        do { try await task.value; XCTFail("Canceled admission") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(model.heavyWorkLease); let count = await release.count; XCTAssertEqual(count, 0)
    }
    func testCanceledPendingAcquisitionCannotReturnReady() async throws {
        let (model, release, _) = try fixture(); let id = UUID()
        let task = Task { try await model.beginHeavyWork(id: id, kind: .imageCreation) }
        try await waitFor { await release.count == 1 }; task.cancel(); await release.finish(0)
        do { try await task.value; XCTFail("Canceled lease became ready") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(model.heavyWorkLease?.phase, .revoked); model.endHeavyWork(id: id)
    }
    func testEverySubmitAndBranchPathRefusesBeforeMutationWhileLeaseHeld() async throws {
        let (model, release, source) = try fixture()
        model.draft = "Existing turn"; model.send(); try await waitFor { !model.isGenerating }
        let original = try XCTUnwrap(model.activeConversation)
        let user = try XCTUnwrap(original.messages.first); let assistant = try XCTUnwrap(original.messages.last)
        let id = UUID(); let task = Task { try await model.beginHeavyWork(id: id, kind: .imageCreation) }
        try await waitFor { await release.count == 1 }; await release.finish(0); try await task.value
        model.draft = "Keep"; model.send(); model.automaticModelsEnabled = true; model.send()
        XCTAssertFalse(model.canAcceptIncomingText)
        XCTAssertThrowsError(try model.acceptIncomingText("Incoming"))
        XCTAssertThrowsError(try model.makeVoiceTurnTicket(ownerID: UUID()))
        let branched = await model.branch(through: user.id); XCTAssertFalse(branched)
        await model.editAndBranch(messageID: user.id, text: "Changed")
        await model.regenerate(messageID: assistant.id)
        XCTAssertEqual(model.conversations.count, 1); XCTAssertEqual(model.activeConversation, original)
        XCTAssertEqual(model.draft, "Keep"); XCTAssertFalse(model.isPreparingAutomaticModel)
        let calls = await source.count; XCTAssertEqual(calls, 1)
        model.endHeavyWork(id: id)
    }
    func testSeriousThermalStateBlocksNewWorkUntilRecoveryAndRelease() async throws {
        let (model, release, _) = try fixture(); model.draft = "Keep"
        model.setHeavyWorkThermalState(.serious)
        try await waitFor { await release.count == 1 }
        XCTAssertFalse(model.canSend)
        do { try await model.beginHeavyWork(id: UUID(), kind: .imageCreation); XCTFail("Thermal admission") }
        catch { XCTAssertEqual(error as? LocalHeavyWorkError, .resourcePressure) }
        model.setHeavyWorkThermalState(.fair)
        XCTAssertFalse(model.canSend, "Release is still pending")
        await release.finish(0); try await waitFor { model.canSend }
        XCTAssertEqual(model.draft, "Keep")
    }
    func testMemoryPressureRevokesOwnerButKeepsAdmissionUntilDismissal() async throws {
        let (model, release, _) = try fixture(); let id = UUID()
        let task = Task { try await model.beginHeavyWork(id: id, kind: .imageCreation) }
        try await waitFor { await release.count == 1 }; await release.finish(0); try await task.value
        model.handleLocalResourcePressure()
        XCTAssertEqual(model.heavyWorkLease?.phase, .revoked)
        try await waitFor { await release.count == 2 }
        model.draft = "Keep"; model.endHeavyWork(id: id); XCTAssertFalse(model.canSend)
        await release.finish(1); try await waitFor { model.canSend }
    }
    func testActiveGenerationRefusesHeavyAdmissionAndImageAcceptanceWithoutInterruption() async throws {
        let (model, release, source) = try fixture()
        model.draft = "Keep generating"; model.send()
        XCTAssertTrue(model.isGenerating)
        let stager = try GeneratedImageStaging(directory: root.appendingPathComponent("Staging"))
        let input = root.appendingPathComponent("not-yet-decoded.png"); try Data([1]).write(to: input)
        let staged = try stager.stage(from: input)
        XCTAssertNil(model.acceptGeneratedImage(staged, concept: "An image", stager: stager))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        do { try await model.beginHeavyWork(id: UUID(), kind: .imageCreation); XCTFail("Admitted during response") }
        catch { XCTAssertEqual(error as? LocalHeavyWorkError, .busy) }
        try await waitFor { !model.isGenerating }
        XCTAssertEqual(model.activeConversation?.messages.last?.state, .complete)
        let calls = await source.count; XCTAssertEqual(calls, 1)
        let releases = await release.count; XCTAssertEqual(releases, 0)
    }

    private func fixture() throws -> (AppModel, ControlledResourceRelease, HeavyReplySource) {
        let release = ControlledResourceRelease(); let source = HeavyReplySource()
        let model = AppModel(store: try SQLiteConversationStore(url: root.appendingPathComponent("test.sqlite")),
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: root.appendingPathComponent("Models")), defaults: defaults,
            resourceReleaser: release)
        model.replaceProviders([ProviderOption(id: "test", title: "Test", detail: "Test only", provider: HeavyReplyProvider(source: source))])
        return (model, release, source)
    }
    private func waitFor(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { XCTFail("Timed out"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
private actor ControlledResourceRelease: LocalResourceReleasing {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var count: Int { waiters.count }
    func unload() async { await withCheckedContinuation { waiters.append($0) } }
    func finish(_ index: Int) { waiters[index].resume() }
}
private actor HeavyReplySource {
    private(set) var count = 0
    func respond() -> AsyncThrowingStream<String, Error> {
        count += 1
        return AsyncThrowingStream { $0.yield("Test response"); $0.finish() }
    }
}
private struct HeavyReplyProvider: AIProvider {
    let id = "test"; let displayName = "Controlled test provider"; let source: HeavyReplySource
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String, Error> { await source.respond() }
}
