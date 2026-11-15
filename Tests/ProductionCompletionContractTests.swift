import XCTest
import Foundation
@testable import JarvisEVO

/// Opt-in actual local inference with a manually selected, explicitly approved
/// checklist. Not model planning, generic autonomy, UI approval or device proof.
/// Run sequentially with other fixture gates; never downloads or copies weights.
@MainActor
final class ProductionCompletionContractTests: XCTestCase {
    func testRequiredApprovedCallsBeforeGroundedAnswer() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ORIVYN_REQUIRE_PRODUCTION_COMPLETION"] == "1" else {
            throw XCTSkip("Explicit completion inference gate is not enabled; no inference pass is claimed.")
        }
        #if !ORIVYN_NATIVE_TOOLS
        XCTFail("Required completion gate needs the combined framework and ORIVYN_NATIVE_TOOLS in app AND test targets.")
        #elseif !targetEnvironment(simulator)
        XCTFail("This host-fixture gate requires the iOS simulator.")
        #else
        guard let path = environment["ORIVYN_COMPLETION_MODEL_DIR"], path.hasPrefix("/"),
              !path.utf8.contains(0), path != "/" else {
            XCTFail("Provide an absolute dedicated ORIVYN_COMPLETION_MODEL_DIR; no implicit fixture download is allowed.")
            return
        }
        let files = FileManager.default
        var cleanupFinished = true
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let attributes = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true else {
            XCTFail("Fixture root must be an existing regular directory, not a symlink."); return
        }
        let descriptor = try ProductionModelFixture.descriptor(environment: environment)
        guard descriptor.id == "qwen3-1.7b-q4_k_m" else {
            XCTFail("This gate evaluates only the explicitly selected pinned Q4 candidate."); return
        }
        // Same lock as the existing production gates. No parallel fixture borrowing.
        let lock = directory.appendingPathComponent(".production-local-agent-test-lock", isDirectory: true)
        try files.createDirectory(at: lock, withIntermediateDirectories: false)
        defer {
            if cleanupFinished {
                do { try files.removeItem(at: lock) }
                catch { XCTFail("Could not remove fixture lock: \(error)") }
            }
        }
        let manifest = directory.appendingPathComponent("installed-models.json")
        let original: Data?
        if files.fileExists(atPath: manifest.path) {
            let values = try manifest.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                XCTFail("Refusing to replace a non-regular fixture manifest."); return
            }
            original = try Data(contentsOf: manifest)
        } else { original = nil }
        defer {
            do {
                if let original { try original.write(to: manifest, options: .atomic) }
                else if files.fileExists(atPath: manifest.path) { try files.removeItem(at: manifest) }
            } catch { XCTFail("Could not restore borrowed fixture manifest: \(error)") }
        }
        try JSONEncoder().encode([descriptor]).write(to: manifest, options: .atomic)

        let root = files.temporaryDirectory.appendingPathComponent("ProductionCompletion-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            if cleanupFinished { try? files.removeItem(at: root) }
            else { XCTFail("Native session did not stop; preserving task evidence at \(root.path)") }
        }
        let suite = "Orivyn.ProductionCompletion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "orivyn.automaticModels")
        defaults.set(false, forKey: "remoteEnabled")
        defaults.set(descriptor.id, forKey: "selectedProviderID")
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let marker = "amber-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        let query = "Cedar acceptance"
        let note = MemoryNote(content: "Cedar acceptance marker: \(marker).")
        try await store.saveMemory(note)
        let model = AppModel(store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: directory), defaults: defaults)
        await model.bootstrap()
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertEqual(model.memories.map(\.id), [note.id])
        XCTAssertEqual(model.memories.map(\.content), [note.content])
        XCTAssertEqual(model.selectedProviderID, descriptor.id)
        let provider = try XCTUnwrap(model.selectedLocalAgentProvider)
        let taskDirectory = root.appendingPathComponent("Tasks", isDirectory: true)
        // Production default stream: never inject scripted decisions into this gate.
        let session = try LocalAgentSession(model: model, directory: taskDirectory)
        let contract = try LocalCompletionContract.parse(#"{"schema":1,"steps":[{"name":"get_app_info","arguments":{}},{"name":"search_memory","arguments":{"query":"Cedar acceptance","limit":2}}]}"#)
        let contractJSON = try contract.encoded()
        let goal = "Read bundled app information, then search saved memory for Cedar acceptance. What exact stored marker does that memory contain? Return the marker from the search result."
        XCTAssertFalse(goal.contains(marker))
        XCTAssertFalse(contractJSON.contains(marker))
        XCTAssertNil(session.snapshot)
        XCTAssertTrue(session.records.isEmpty)
        XCTAssertNil(model.heavyWorkLease)
        let started = Date()
        session.prepareCompletion(goal: goal, contract: contract)
        let review = try XCTUnwrap(session.proposedCompletion)
        XCTAssertTrue(review.goal.utf8.elementsEqual(goal.utf8))
        XCTAssertEqual(try review.contract.encoded(), contractJSON)
        XCTAssertNil(session.error)
        XCTAssertNil(session.snapshot, "Review must not create or execute a task")
        XCTAssertTrue(session.records.isEmpty)
        XCTAssertFalse(session.isRunning, "Manual checklist review must not run a model")
        XCTAssertNil(model.heavyWorkLease)
        attach("production-completion-review", "goal=\(review.goal)\ncontract=\(contractJSON)\nmodelSHA256=\(descriptor.sha256)\nnoTask=true\nnoRunningWork=\(!session.isRunning)")

        session.approveCompletion(goal: goal, contract: contract)
        XCTAssertNil(session.error)
        XCTAssertNil(session.proposedCompletion)
        let approved = try XCTUnwrap(session.snapshot)
        XCTAssertEqual(approved.version, 3)
        XCTAssertEqual(approved.status, "ready")
        XCTAssertEqual(approved.steps, 0)
        XCTAssertTrue(approved.history.isEmpty)
        XCTAssertNil(approved.pending)
        XCTAssertNil(approved.answer)
        XCTAssertNil(approved.readPlan)
        XCTAssertEqual(approved.completionContract, contract)
        XCTAssertEqual(approved.approvalRevision, 0)
        XCTAssertTrue(approved.goal.utf8.elementsEqual(goal.utf8))
        XCTAssertFalse(session.isRunning, "Approval must not execute a model or local operations")
        XCTAssertNil(model.heavyWorkLease)
        XCTAssertEqual(session.records.count, 1)
        let id = approved.id
        let taskStore = try LocalAgentStore(directory: taskDirectory)
        let approvedRaw = try taskStore.load(id: id)
        let approvedDisk = try JSONDecoder().decode(LocalAgentSnapshot.self, from: Data(approvedRaw.utf8))
        XCTAssertEqual(approvedDisk.version, 3)
        XCTAssertEqual(approvedDisk.completionContract, contract)
        XCTAssertEqual(approvedDisk.approvalRevision, 0)
        XCTAssertEqual(approvedDisk.status, "ready")
        XCTAssertEqual(approvedDisk.steps, 0)
        XCTAssertTrue(approvedDisk.history.isEmpty)
        XCTAssertNil(approvedDisk.pending)
        XCTAssertNil(approvedDisk.answer)
        XCTAssertFalse(approvedRaw.contains(marker), "Random answer must not leak into the approved task")
        // Repeated approval is a no-op, not a second task or an implicit Run.
        session.approveCompletion(goal: goal, contract: contract)
        XCTAssertEqual(session.records.count, 1)
        XCTAssertEqual(session.snapshot?.id, id)
        XCTAssertFalse(session.isRunning)
        attach("production-completion-approved", approvedRaw)

        cleanupFinished = false
        session.run()
        XCTAssertTrue(session.isRunning, "Explicit Run must start actual model inference")
        let runFinished = await waitForWork(session, seconds: 600)
        cleanupFinished = await joined(session, provider: provider, model: model)
        let persisted = try taskStore.load(id: id)
        attach("production-completion-executed", "scope=real simulator inference with explicit manually approved checklist; not generic planning or UI approval\nmodelSHA256=\(descriptor.sha256)\nelapsedSeconds=\(Date().timeIntervalSince(started))\ntimeout=\(!runFinished)\ncleanupFinished=\(cleanupFinished)\nsessionError=\(session.error ?? "none")\nstate=\(persisted)")
        XCTAssertTrue(runFinished, "Actual inference exceeded 600 seconds")
        XCTAssertTrue(cleanupFinished, "Inference must join and release its lease")
        XCTAssertNil(model.heavyWorkLease)
        XCTAssertNil(session.error)
        let snapshot = try XCTUnwrap(session.snapshot)
        XCTAssertEqual(snapshot.version, 3)
        XCTAssertEqual(snapshot.status, "answered")
        XCTAssertEqual(snapshot.steps, 2)
        XCTAssertEqual(snapshot.completionContract, contract)
        XCTAssertEqual(snapshot.approvalRevision, 0)
        XCTAssertNil(snapshot.pending)
        XCTAssertEqual(snapshot.history.map(\.name), ["get_app_info", "search_memory"])
        XCTAssertEqual(snapshot.history.map(\.outcome), ["succeeded", "succeeded"])
        guard snapshot.history.count == 2 else { XCTFail("Exact two-call history is required"); return }
        XCTAssertEqual(snapshot.history[0].operationID, id + ":1")
        XCTAssertEqual(snapshot.history[1].operationID, id + ":2")
        XCTAssertEqual(snapshot.history[0].arguments, .object([:]))
        XCTAssertEqual(snapshot.history[1].arguments, .object(["query": .string(query), "limit": .integer(2)]))
        XCTAssertTrue(snapshot.history[0].result?.contains(marker) == false, "Marker must not be present before memory search")
        let memoryResult = try XCTUnwrap(snapshot.history[1].result)
        let memoryObject = try XCTUnwrap(MCPJSONValue.parse(Data(memoryResult.utf8), maximumBytes: 4096).objectValue)
        let matches = try XCTUnwrap(memoryObject["memories"]?.arrayValue)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.objectValue?["id"]?.stringValue?.lowercased(), note.id.uuidString.lowercased())
        XCTAssertTrue(matches.first?.objectValue?["excerpt"]?.stringValue?.contains(marker) == true)
        XCTAssertEqual(memoryObject["searchLimited"]?.boolValue, false)
        XCTAssertEqual(memoryObject["resultsLimited"]?.boolValue, false)
        XCTAssertTrue(snapshot.answer?.contains(marker) == true, "Actual model answer must copy the unpredictable stored marker")
        let disk = try JSONDecoder().decode(LocalAgentSnapshot.self, from: Data(persisted.utf8))
        XCTAssertEqual(disk.version, snapshot.version)
        XCTAssertEqual(disk.completionContract, contract)
        XCTAssertEqual(disk.approvalRevision, snapshot.approvalRevision)
        XCTAssertEqual(disk.status, snapshot.status)
        XCTAssertEqual(disk.steps, snapshot.steps)
        XCTAssertEqual(disk.answer, snapshot.answer)
        XCTAssertEqual(disk.history.map(\.operationID), snapshot.history.map(\.operationID))
        XCTAssertEqual(disk.history.map(\.result), snapshot.history.map(\.result))
        XCTAssertNil(disk.pending)
        print("ORIVYN_PRODUCTION_COMPLETION_GATE_COMPLETED")
        #endif
    }

    private func attach(_ name: String, _ text: String) {
        let evidence = XCTAttachment(string: text)
        evidence.name = name; evidence.lifetime = .keepAlways; add(evidence)
    }
    private func waitForWork(_ session: LocalAgentSession, seconds: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while session.isRunning && ContinuousClock.now < deadline && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let finished = !session.isRunning && !Task.isCancelled
        if !finished { session.stop(cancelTask: true) }
        return finished
    }
    private func joined(_ session: LocalAgentSession, provider: LocalAIProvider, model: AppModel) async -> Bool {
        await Task { @MainActor in
            let deadline = ContinuousClock.now + .seconds(120)
            while session.isRunning && ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !session.isRunning else { return false }
            await provider.unload()
            return model.heavyWorkLease == nil
        }.value
    }
}
