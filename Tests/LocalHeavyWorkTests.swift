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
    func testOpeningAnotherAgentSessionDoesNotRecoverLiveWork() async throws {
        let (model, release, _) = try fixture()
        let directory = root.appendingPathComponent("AgentRecovery")
        let core = try LocalAgentCore(), store = try LocalAgentStore(directory: directory)
        let taskID = UUID().uuidString.lowercased()
        let ready = try core.call("create", ["Read app info", taskID])
        let running = try core.call("acceptDecision", [ready, "{\"type\":\"tool\",\"name\":\"get_app_info\",\"arguments\":{}}"])
        try store.save(running, id: taskID)
        let owner = UUID()
        let preparing = Task { try await model.beginHeavyWork(id: owner, kind: .localAgent) }
        try await waitFor { await release.count == 1 }
        let second = try LocalAgentSession(model: model, directory: directory)
        try second.reloadRecords()
        XCTAssertEqual(try store.load(id: taskID), running)
        await release.finish(0); try await preparing.value
        model.endHeavyWork(id: owner)
        try second.reloadRecords()
        XCTAssertEqual(try core.snapshot(store.load(id: taskID)).status, "interrupted")
    }
    func testOpeningAnotherVerifiedSessionDoesNotRecoverLiveWork() async throws {
        let (model, _, _) = try fixture()
        let directory = root.appendingPathComponent("VerifiedRecovery")
        let core = try VerifiedLocalPlanCore(), store = try LocalAgentStore(directory: directory)
        let taskID = UUID().uuidString.lowercased()
        let ready = try core.call("create", ["{\"appInfo\":true,\"installedModels\":false,\"searchQuery\":null}", taskID])
        let running = try core.call("next", [ready])
        try store.save(running, id: taskID)
        let owner = UUID(); XCTAssertTrue(model.beginVerifiedReads(id: owner))
        let second = try VerifiedLocalReadSession(model: model, directory: directory)
        try second.reload()
        XCTAssertEqual(try store.load(id: taskID), running)
        model.endVerifiedReads(id: owner)
        try second.reload()
        XCTAssertEqual(try core.snapshot(store.load(id: taskID)).status, "interrupted")
    }
    func testSecondSessionCannotArchiveWhileSharedAgentLeaseIsUnwinding() async throws {
        let (model, release, _) = try fixture()
        let directory = root.appendingPathComponent("AgentTasks")
        let first = try LocalAgentSession(model: model, directory: directory)
        first.create(goal: "Read app info")
        let savedID = try XCTUnwrap(first.snapshot?.id)
        let second = try LocalAgentSession(model: model, directory: directory)
        second.select(id: savedID)
        let id = UUID()
        let preparing = Task { try await model.beginHeavyWork(id: id, kind: .localAgent) }
        try await waitFor { await release.count == 1 }
        await release.finish(0); try await preparing.value
        let finishing = Task { await model.finishLocalAgentWork(id: id) }
        try await waitFor { await release.count == 2 }
        XCTAssertFalse(second.canManageSavedTasks)
        second.archiveSelected()
        XCTAssertEqual(second.snapshot?.id, savedID)
        XCTAssertEqual(try LocalAgentStore(directory: directory).records().total, 1)
        await release.finish(1); await finishing.value
        XCTAssertTrue(second.canManageSavedTasks)
        second.archiveSelected()
        XCTAssertEqual(try LocalAgentStore(directory: directory).records().total, 0)
        XCTAssertEqual(try LocalAgentStore(directory: directory).archivedRecords().total, 1)
    }
    func testVerifiedPlanAcceptsActualBundledAppInfoWithDetailsAndBudgetMetadata() throws {
        let (model, _, _) = try fixture()
        let result = try LocalReadTools.execute(name: "get_app_info", arguments: .object([:]), model: model)
        let payload = try MCPJSONValue.parse(Data(result.utf8), maximumBytes: 4096)
        let capabilities = try XCTUnwrap(payload.objectValue?["capabilities"]?.arrayValue)
        XCTAssertFalse(capabilities.isEmpty, "Exercise actual bundled facts, not an empty synthetic payload")
        XCTAssertTrue(capabilities.allSatisfy { $0.objectValue?["detail"]?.stringValue?.isEmpty == false })
        let core = try VerifiedLocalPlanCore()
        let state = try core.call("create", [#"{"appInfo":true,"installedModels":false,"searchQuery":null}"#, UUID().uuidString])
        let pending = try core.call("next", [state])
        let operation = try XCTUnwrap(try core.snapshot(pending).pending?.operationID)
        let envelope = try MCPJSONValue.object(["operationID": .string(operation), "resultJSON": .string(result)]).encoded(maximumBytes: 32_768)
        let done = try core.call("record", [pending, String(decoding: envelope, as: UTF8.self)])
        XCTAssertEqual(try core.snapshot(done).status, "complete")
        XCTAssertEqual(try core.call("recover", [done]), done)
        let report = try MCPJSONValue.parse(Data(core.call("report", [done]).utf8), maximumBytes: 65_536)
        let evidence = try XCTUnwrap(report.objectValue?["evidence"]?.arrayValue?.first?.objectValue?["result"])
        XCTAssertEqual(evidence, payload, "Prerequisites and source omission facts must survive exactly")
    }

    func testVerifiedReadsUseActualLocalStateWithoutLoadingAnInferenceModel() async throws {
        let (model, release, _) = try fixture()
        model.draft = "Preserve this draft"
        let session = try VerifiedLocalReadSession(model: model, directory: root.appendingPathComponent("VerifiedReads"))
        session.create(appInfo: true, installedModels: true, searchQuery: nil)
        session.run()
        try await waitFor { await MainActor.run { !session.isRunning } }
        XCTAssertEqual(session.snapshot?.status, "complete", session.error ?? session.report)
        XCTAssertEqual(session.snapshot?.completed, 2)
        XCTAssertEqual(session.records.first(where: { $0.id == session.snapshot?.id })?.completed, 2)
        XCTAssertTrue(session.report.contains("Orivyn"))
        XCTAssertTrue(session.report.contains("totalInstalled"))
        XCTAssertEqual(model.draft, "Preserve this draft")
        let unloads = await release.count
        XCTAssertEqual(unloads, 0)
        XCTAssertNil(model.verifiedReadOwner)
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

    func testVirtualDesktopLeaseSurvivesUntilRuntimeStopAcknowledged() async throws {
        let (model, release, _) = try fixture()
        model.draft = "Keep this task"
        let runtime = ControlledDesktopRuntime()
        let session = VirtualDesktopSession(model: model, runtime: runtime)
        session.start()
        try await waitFor { await release.count == 1 }
        await release.finish(0)
        try await waitFor { runtime.started }
        let closing = Task { await session.close() }
        try await waitFor { runtime.stopGate != nil }
        XCTAssertNotNil(model.heavyWorkLease)
        XCTAssertFalse(model.canSend)
        runtime.stopGate?.resume(returning: true)
        let result = await closing.value
        XCTAssertTrue(result)
        XCTAssertNil(model.heavyWorkLease)
        XCTAssertTrue(model.canSend)
        XCTAssertEqual(model.draft, "Keep this task")
    }

    func testUncertainDesktopStopRetainsRevokedLease() async throws {
        let (model, release, _) = try fixture()
        model.draft = "Keep this task"
        let runtime = ControlledDesktopRuntime()
        let session = VirtualDesktopSession(model: model, runtime: runtime)
        session.start()
        try await waitFor { await release.count == 1 }
        await release.finish(0)
        try await waitFor { runtime.started }
        let closing = Task { await session.close() }
        try await waitFor { runtime.stopGate != nil }
        runtime.stopGate?.resume(returning: false)
        let result = await closing.value
        XCTAssertFalse(result)
        XCTAssertEqual(model.heavyWorkLease?.phase, .revoked)
        XCTAssertFalse(model.canSend)
    }

    func testDesktopCloseDuringPreparationCannotStartGuestOrReleaseEarly() async throws {
        let (model, release, _) = try fixture()
        let runtime = ControlledDesktopRuntime()
        let session = VirtualDesktopSession(model: model, runtime: runtime)
        session.start()
        try await waitFor { await release.count == 1 }
        let closing = Task { await session.close() }
        await Task.yield()
        XCTAssertFalse(runtime.started)
        XCTAssertNil(runtime.stopGate)
        XCTAssertNotNil(model.heavyWorkLease)
        await release.finish(0)
        try await waitFor { runtime.stopGate != nil }
        XCTAssertFalse(runtime.started)
        runtime.stopGate?.resume(returning: true)
        let result = await closing.value
        XCTAssertTrue(result)
        XCTAssertNil(model.heavyWorkLease)
    }

    func testAgentLeaseWaitsForActualModelUnloadAfterTaskEnds() async throws {
        let (model, release, _) = try fixture()
        model.draft = "Keep this draft"
        let id = UUID()
        let acquiring = Task { try await model.beginHeavyWork(id: id, kind: .localAgent) }
        try await waitFor { await release.count == 1 }
        await release.finish(0); try await acquiring.value
        let finishing = Task { await model.finishLocalAgentWork(id: id) }
        try await waitFor { await release.count == 2 }
        XCTAssertEqual(model.heavyWorkLease?.phase, .revoked)
        XCTAssertFalse(model.canSend)
        await release.finish(1); await finishing.value
        XCTAssertNil(model.heavyWorkLease)
        XCTAssertTrue(model.canSend)
        XCTAssertEqual(model.draft, "Keep this draft")
    }

    func testModelRemovalOwnsAdmissionUntilReleaseAndDeletionFinish() async throws {
        let (model, release, source) = try fixture()
        let descriptor = try await installTestModel(model)
        model.draft = "Keep my next request"
        let task = Task { await model.removeModel(descriptor) }
        try await waitFor { await release.count == 1 }
        XCTAssertTrue(model.isRemovingModel)
        XCTAssertFalse(model.canSend)
        XCTAssertFalse(model.canBeginHeavyWork)
        XCTAssertThrowsError(try model.makeVoiceTurnTicket(ownerID: UUID()))
        model.send()
        XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(model.draft, "Keep my next request")
        await model.removeModel(descriptor)
        let releases = await release.count; XCTAssertEqual(releases, 1)
        model.downloadModel(LocalModelCatalog.defaultModel)
        XCTAssertNil(model.downloadingModelID)
        await model.importModel(from: root.appendingPathComponent("another.gguf"))
        XCTAssertTrue(model.isRemovingModel)
        await release.finish(0); await task.value
        XCTAssertFalse(model.isRemovingModel)
        XCTAssertTrue(model.canSend)
        XCTAssertFalse(model.installedModels.contains { $0.id == descriptor.id })
        let calls = await source.count; XCTAssertEqual(calls, 0)
    }

    func testCancelledRemovalRetainsModelAndReleasesAdmission() async throws {
        let (model, release, _) = try fixture()
        let descriptor = try await installTestModel(model)
        model.draft = "Keep"
        let task = Task { await model.removeModel(descriptor) }
        try await waitFor { await release.count == 1 }
        task.cancel()
        XCTAssertFalse(model.canSend, "Cancellation must await actual resource release")
        await release.finish(0); await task.value
        XCTAssertFalse(model.isRemovingModel)
        XCTAssertTrue(model.canSend)
        XCTAssertTrue(model.installedModels.contains { $0.id == descriptor.id })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Models").appendingPathComponent(descriptor.fileName).path))
    }

    func testFailedRemovalReleasesAdmission() async throws {
        let (model, release, _) = try fixture()
        model.draft = "Keep"
        let task = Task { await model.removeModel(LocalModelCatalog.defaultModel) }
        try await waitFor { await release.count == 1 }
        await release.finish(0); await task.value
        XCTAssertFalse(model.isRemovingModel)
        XCTAssertTrue(model.canSend)
        XCTAssertNotNil(model.errorMessage)
    }

    private func installTestModel(_ model: AppModel) async throws -> LocalModelDescriptor {
        // Storage-only GGUF fixture. Never passed to native inference.
        let input = root.appendingPathComponent("fixture.gguf")
        try Data([0x47, 0x47, 0x55, 0x46, 3, 0, 0, 0] + Array(repeating: UInt8(0), count: 32)).write(to: input)
        await model.importModel(from: input)
        return try XCTUnwrap(model.installedModels.first)
    }

    private func fixture() throws -> (AppModel, ControlledResourceRelease, HeavyReplySource) {
        let release = ControlledResourceRelease(); let source = HeavyReplySource()
        let model = AppModel(offlineAutoSelection: false, store: try SQLiteConversationStore(url: root.appendingPathComponent("test.sqlite")),
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

@MainActor
private final class ControlledDesktopRuntime: VirtualDesktopRuntime {
    var started = false
    var stopGate: CheckedContinuation<Bool, Never>?
    func startRuntime() -> Bool { started = true; return true }
    func stopAndWait() async -> Bool {
        await withCheckedContinuation { stopGate = $0 }
    }
}

