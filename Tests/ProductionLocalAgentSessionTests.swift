import XCTest
import Foundation
@testable import JarvisEVO

/// Opt-in simulator integration, not a general autonomy/accuracy gate.
/// Run sequentially with the native-tools fixture gate. The caller provisions the
/// pinned Qwen file in a dedicated host directory; this test never downloads or
/// copies weights. It temporarily replaces and then restores its manifest bytes.
@MainActor
final class ProductionLocalAgentSessionTests: XCTestCase {
    func testRequiredSearchThenReadGroundedAnswer() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ORIVYN_REQUIRE_PRODUCTION_LOCAL_AGENT"] == "1" else {
            throw XCTSkip("Explicit production LocalAgentSession gate is not enabled; no inference pass is claimed.")
        }
        #if !ORIVYN_NATIVE_TOOLS
        XCTFail("Required agent gate needs the combined framework and ORIVYN_NATIVE_TOOLS in app AND test targets.")
        #elseif !targetEnvironment(simulator)
        XCTFail("This host-fixture gate requires the iOS simulator.")
        #else
        guard let path = environment["ORIVYN_LOCAL_AGENT_MODEL_DIR"], path.hasPrefix("/"),
              !path.utf8.contains(0), path != "/" else {
            XCTFail("Provide an absolute dedicated ORIVYN_LOCAL_AGENT_MODEL_DIR; no implicit fixture download is allowed.")
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

        // Fail on another instance or an unrecovered prior run. This lock does not
        // coordinate other test classes: the caller must run fixture gates serially.
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

        let root = files.temporaryDirectory.appendingPathComponent("ProductionLocalAgent-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            if cleanupFinished { try? files.removeItem(at: root) }
            else { XCTFail("Native session did not stop; preserving task evidence at \(root.path)") }
        }
        let suite = "Orivyn.ProductionLocalAgent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "orivyn.automaticModels")
        defaults.set(false, forKey: "remoteEnabled")
        defaults.set(descriptor.id, forKey: "selectedProviderID")
        let store = try SQLiteConversationStore(url: root.appendingPathComponent("history.sqlite"))
        let marker = "amber-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        // The requested search key exists ONLY in the title; its search result
        // contains the title rather than the marker-bearing message. Assertions
        // below reject any alternate search that exposes the marker directly.
        let message = String(repeating: "Synthetic background. ", count: 10) + "Stored verification marker: \(marker)."
        let conversation = Conversation(title: "Orchid ledger", messages: [ChatMessage(role: .user, content: message)])
        try await store.save(conversation)
        let model = AppModel(store: store,
            attachmentService: try AttachmentService(directory: root.appendingPathComponent("Attachments")),
            modelStore: try LocalModelStore(root: directory), defaults: defaults)
        await model.bootstrap()
        XCTAssertEqual(model.conversations.count, 1)
        XCTAssertEqual(model.conversations.first?.messages.first?.content, message)
        XCTAssertEqual(model.selectedProviderID, descriptor.id)
        let provider = try XCTUnwrap(model.selectedLocalAgentProvider)
        let taskDirectory = root.appendingPathComponent("Tasks", isDirectory: true)
        let session = try LocalAgentSession(model: model, directory: taskDirectory)
        let goal = "Find the saved conversation titled Orchid ledger using search_conversations. Then use read_conversation on its returned ID, messageIndex 0, offset 0. What exact stored verification marker does that message contain? Read the message before answering; do not guess."
        XCTAssertFalse(goal.contains(marker))
        session.create(goal: goal)
        XCTAssertNil(session.error)
        XCTAssertEqual(session.snapshot?.status, "ready")
        XCTAssertTrue(session.snapshot?.history.isEmpty == true)
        XCTAssertFalse(session.isRunning, "Create must not dispatch inference")
        XCTAssertNil(model.heavyWorkLease)
        let id = try XCTUnwrap(session.snapshot?.id)
        let started = Date()
        cleanupFinished = false
        session.run()
        XCTAssertTrue(session.isRunning, "The required run must actually start")
        let deadline = ContinuousClock.now + .seconds(600)
        while session.isRunning && ContinuousClock.now < deadline && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let exceededDeadline = session.isRunning
        if exceededDeadline { session.stop(cancelTask: true) }
        // An independent task completes teardown even if XCTest cancels this task.
        cleanupFinished = await Task { @MainActor in
            let cleanupDeadline = ContinuousClock.now + .seconds(120)
            while session.isRunning && ContinuousClock.now < cleanupDeadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !session.isRunning else { return false }
            await provider.unload()
            return model.heavyWorkLease == nil
        }.value
        let persisted = try LocalAgentStore(directory: taskDirectory).load(id: id)
        let evidence = XCTAttachment(string: "scope=one real simulator LocalAgentSession search/read task\nmodelSHA256=\(descriptor.sha256)\nelapsedSeconds=\(Date().timeIntervalSince(started))\ntimeout=\(exceededDeadline)\ncleanupFinished=\(cleanupFinished)\nsessionError=\(session.error ?? "none")\nstate=\(persisted)")
        evidence.name = "production-local-agent-search-read"; evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertFalse(exceededDeadline, "Actual multistep inference exceeded 600 seconds")
        XCTAssertTrue(cleanupFinished, "Session must join inference and release its lease")
        XCTAssertNil(model.heavyWorkLease)
        XCTAssertNil(session.error)
        let snapshot = try XCTUnwrap(session.snapshot)
        XCTAssertEqual(snapshot.status, "answered")
        XCTAssertTrue(snapshot.answer?.contains(marker) == true, "Answer must copy the unpredictable stored marker")
        XCTAssertTrue(snapshot.history.allSatisfy { $0.outcome == "succeeded" })
        let searchIndex = try XCTUnwrap(snapshot.history.firstIndex { $0.name == "search_conversations" && $0.outcome == "succeeded" })
        let readIndex = try XCTUnwrap(snapshot.history.firstIndex { $0.name == "read_conversation" && $0.outcome == "succeeded" && $0.result?.contains(marker) == true })
        XCTAssertLessThan(searchIndex, readIndex)
        XCTAssertTrue(snapshot.history.filter { $0.name == "search_conversations" }.allSatisfy { $0.result?.contains(marker) == false }, "Search must not leak the answer into its excerpt")
        XCTAssertTrue(snapshot.history[..<readIndex].allSatisfy { $0.result?.contains(marker) != true }, "Marker must first arrive through the conversation read")
        XCTAssertEqual(snapshot.history[readIndex].arguments.objectValue?["id"]?.stringValue?.lowercased(), conversation.id.uuidString.lowercased())
        let diskSnapshot = try JSONDecoder().decode(LocalAgentSnapshot.self, from: Data(persisted.utf8))
        XCTAssertEqual(diskSnapshot.status, snapshot.status)
        XCTAssertEqual(diskSnapshot.answer, snapshot.answer)
        XCTAssertEqual(diskSnapshot.history.map(\.operationID), snapshot.history.map(\.operationID))
        print("ORIVYN_PRODUCTION_LOCAL_AGENT_GATE_COMPLETED")
        #endif
    }
}
