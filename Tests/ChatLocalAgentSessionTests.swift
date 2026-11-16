import XCTest
import CryptoKit
@testable import JarvisEVO

/// Deterministic model-output enforcement, not real inference or grammar proof.
@MainActor
final class ChatLocalAgentSessionTests: XCTestCase {
    private var root:URL!, defaults:UserDefaults!, suite:String!
    override func setUp() async throws {
        root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        suite="Orivyn.CompletionSession."+UUID().uuidString; defaults=UserDefaults(suiteName:suite)!
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:root)
    }
    private func fixture(_ script: Script) async throws -> (AppModel,LocalAgentSession) {
        let modelRoot=root.appendingPathComponent("models")
        try FileManager.default.createDirectory(at:modelRoot,withIntermediateDirectories:true)
        // Metadata fixture only. Never passed to an inference runtime by these tests.
        let bytes=Data([0x47,0x47,0x55,0x46,3,0,0,0]+Array(repeating:UInt8(0),count:16))
        let digest=SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
        let descriptor=LocalModelDescriptor(id:"completion-fixture",name:"Synthetic metadata",fileName:"fixture.gguf",downloadURL:nil,sha256:digest,byteCount:Int64(bytes.count),license:"test",sourceURL:nil)
        try bytes.write(to:modelRoot.appendingPathComponent(descriptor.fileName))
        try JSONEncoder().encode([descriptor]).write(to:modelRoot.appendingPathComponent("installed-models.json"))
        defaults.set(descriptor.id,forKey:"selectedProviderID")
        let modelStore=try LocalModelStore(root:modelRoot)
        _ = try await modelStore.verifiedURL(for:descriptor)
        let model=AppModel(store:try SQLiteConversationStore(url:root.appendingPathComponent("history.sqlite")),attachmentService:try AttachmentService(directory:root.appendingPathComponent("attachments")),modelStore:modelStore,defaults:defaults)
        await model.bootstrap()
        _ = try XCTUnwrap(model.selectedLocalAgentProvider)
        let session=try LocalAgentSession(model:model,directory:root.appendingPathComponent("tasks"),decisionStream:{ request,_ in try await script.stream(request) })
        return (model,session)
    }
    private var contract:LocalCompletionContract { get throws {
        try .parse(#"{"schema":1,"steps":[{"name":"get_app_info","arguments":{}},{"name":"list_models","arguments":{}}]}"#)
    }}
    private func approve(_ session:LocalAgentSession, goal:String="Inspect app and models") throws {
        session.prepareCompletion(goal:goal,contract:try contract)
        XCTAssertNotNil(session.proposedCompletion); XCTAssertTrue(session.records.isEmpty)
        session.approveCompletion(goal:goal,contract:try contract)
        XCTAssertEqual(session.snapshot?.status,"ready"); XCTAssertEqual(session.snapshot?.steps,0)
    }
    private func waitUntil(_ condition: @escaping @MainActor ()->Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(nanoseconds:25_000_000) }
        XCTFail("Bounded session condition timed out")
    }
    func testChatOriginSurvivesReloadAndCrossConversationCannotRun() async throws {
        let (model, session) = try await fixture(Script([]))
        _ = await model.newConversation()
        let origin = try XCTUnwrap(model.selectedConversationID)
        let context = ChatLocalTaskContext(conversationID: origin, conversationRevision: model.pluginResultConversationContext, providerRevision: model.pluginProposalProviderContext)
        try session.bindConversation(context)
        try approve(session)
        let id = try XCTUnwrap(session.snapshot?.id)
        XCTAssertEqual(try LocalAgentStore(directory: root.appendingPathComponent("tasks")).origin(id: id), origin)
        _ = await model.newConversation()
        session.run()
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.snapshot?.history.count, 0)
        XCTAssertNotNil(session.error)
        model.selectConversation(origin)
        let restored = try LocalAgentSession(model: model, directory: root.appendingPathComponent("tasks"))
        restored.select(id: id)
        XCTAssertEqual(restored.snapshot?.id, id)
        XCTAssertEqual(restored.snapshot?.status, "ready")
        XCTAssertFalse(restored.isRunning)
    }
    func testChatApprovalRejectsProviderRoundTrip() async throws {
        let (model, session) = try await fixture(Script([]))
        _ = await model.newConversation()
        let origin = try XCTUnwrap(model.selectedConversationID)
        try session.bindConversation(ChatLocalTaskContext(conversationID: origin, conversationRevision: model.pluginResultConversationContext, providerRevision: model.pluginProposalProviderContext))
        session.prepareCompletion(goal: "Inspect app and models", contract: try contract)
        let provider = model.selectedProviderID
        model.selectedProviderID = "missing"; model.selectedProviderID = provider
        session.approveCompletion(goal: "Inspect app and models", contract: try contract)
        XCTAssertTrue(session.records.isEmpty)
        XCTAssertNotNil(session.error)
    }
    func testChatSelectionRoundTripDuringDecisionCannotDispatch() async throws {
        let script = Script([]); script.suspend = true
        let (model, session) = try await fixture(script)
        _ = await model.newConversation()
        let origin = try XCTUnwrap(model.selectedConversationID)
        try session.bindConversation(ChatLocalTaskContext(conversationID: origin, conversationRevision: model.pluginResultConversationContext, providerRevision: model.pluginProposalProviderContext))
        try approve(session); session.run()
        try await waitUntil { script.continuation != nil }
        model.selectedConversationID = UUID(); model.selectedConversationID = origin
        script.continuation?.yield(#"{"type":"tool","name":"get_app_info","arguments":{}}"#)
        script.continuation?.finish()
        try await waitUntil { !session.isRunning }
        XCTAssertEqual(session.snapshot?.history.count, 0)
        XCTAssertNotEqual(session.snapshot?.status, "answered")
    }
    func testChatResumeRetainsCompletedEvidenceWithoutReplayingFirstRead() async throws {
        let first = Script([#"{"type":"tool","name":"get_app_info","arguments":{}}"#])
        first.suspendAfter = 1
        let (model, session) = try await fixture(first)
        _ = await model.newConversation()
        let origin = try XCTUnwrap(model.selectedConversationID)
        try session.bindConversation(ChatLocalTaskContext(conversationID: origin, conversationRevision: model.pluginResultConversationContext, providerRevision: model.pluginProposalProviderContext))
        try approve(session); session.run()
        try await waitUntil { first.continuation != nil }
        XCTAssertEqual(session.snapshot?.history.map(\.name), ["get_app_info"])
        let id = try XCTUnwrap(session.snapshot?.id)
        session.stop(cancelTask: false); first.continuation?.finish()
        try await waitUntil { !session.isRunning }
        let next = Script([#"{"type":"tool","name":"list_models","arguments":{}}"#,
                           #"{"type":"answer","text":"Recorded both reads."}"#])
        let restored = try LocalAgentSession(model: model, directory: root.appendingPathComponent("tasks"), decisionStream: { request, _ in try await next.stream(request) })
        restored.select(id: id)
        XCTAssertFalse(restored.isRunning)
        restored.run()
        try await waitUntil { !restored.isRunning }
        XCTAssertEqual(restored.snapshot?.history.map(\.name), ["get_app_info", "list_models"])
        XCTAssertEqual(restored.snapshot?.status, "answered")
    }
    @MainActor private final class Script {
        var outputs:[String],requests:[GenerationRequest]=[],suspend=false
        var suspendAfter: Int?
        var continuation:AsyncThrowingStream<String,Error>.Continuation?
        init(_ outputs:[String]) { self.outputs=outputs }
        func stream(_ request:GenerationRequest) async throws -> AsyncThrowingStream<String,Error> {
            requests.append(request)
            if suspend || suspendAfter.map({ requests.count > $0 }) == true { return AsyncThrowingStream { continuation=$0 } }
            guard !outputs.isEmpty else { throw LocalAgentError.invalidState }
            let next=outputs.removeFirst()
            return AsyncThrowingStream { $0.yield(next);$0.finish() }
        }
    }
}
