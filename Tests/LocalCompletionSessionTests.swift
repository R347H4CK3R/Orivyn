import XCTest
@testable import JarvisEVO

/// Deterministic model-output enforcement, not real inference or grammar proof.
@MainActor
final class LocalCompletionSessionTests: XCTestCase {
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
        let descriptor=LocalModelDescriptor(id:"completion-fixture",name:"Synthetic metadata",fileName:"fixture.gguf",downloadURL:nil,sha256:String(repeating:"a",count:64),byteCount:1,license:"test",sourceURL:nil)
        try Data([0]).write(to:modelRoot.appendingPathComponent(descriptor.fileName))
        try JSONEncoder().encode([descriptor]).write(to:modelRoot.appendingPathComponent("installed-models.json"))
        defaults.set(descriptor.id,forKey:"selectedProviderID")
        let model=AppModel(store:try SQLiteConversationStore(url:root.appendingPathComponent("history.sqlite")),attachmentService:try AttachmentService(directory:root.appendingPathComponent("attachments")),modelStore:try LocalModelStore(root:modelRoot),defaults:defaults)
        await model.bootstrap()
        XCTAssertNotNil(model.selectedLocalAgentProvider)
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
    func testCorrectTwoStepExecutionUsesActualToolsAndNeverStartsOnApproval() async throws {
        let script=Script([#"{"type":"tool","name":"get_app_info","arguments":{}}"#,#"{"type":"tool","name":"list_models","arguments":{}}"#,#"{"type":"answer","text":"Unverified summary"}"#])
        let (_,session)=try await fixture(script); try approve(session,goal:"  Inspect app and models\n")
        XCTAssertEqual(session.snapshot?.goal,"  Inspect app and models\n")
        XCTAssertEqual(script.requests.count,0)
        session.run(); try await waitUntil { !session.isRunning }
        XCTAssertEqual(session.snapshot?.status,"answered")
        XCTAssertEqual(session.snapshot?.history.map(\.name),["get_app_info","list_models"])
        XCTAssertEqual(session.snapshot?.history.map(\.outcome),["succeeded","succeeded"])
        XCTAssertTrue(session.snapshot?.history.last?.result?.contains("Synthetic metadata") == true)
        XCTAssertEqual(script.requests.count,3)
        XCTAssertEqual(script.requests.map { $0.localCompletionPolicy?.canAnswer },[false,false,true])
        session.approveCompletion(goal:"Inspect app and models",contract:try contract)
        XCTAssertEqual(session.records.count,1,"Approval is one-shot")
    }
    func testPrematureAnswerAndReorderedCallNeverDispatch() async throws {
        // Separate fixtures preserve each task and never share mutable state.
        let script=Script([#"{"type":"answer","text":"done"}"#])
        let (_,session)=try await fixture(script); try approve(session);session.run()
        try await waitUntil { !session.isRunning }
        XCTAssertEqual(session.snapshot?.status,"failed");XCTAssertEqual(session.snapshot?.history.count,0)
        script.outputs=[#"{"type":"tool","name":"list_models","arguments":{}}"#]
        session.prepareCompletion(goal:"Inspect app and models",contract:try contract)
        session.approveCompletion(goal:"Inspect app and models",contract:try contract);session.run()
        try await waitUntil { !session.isRunning }
        XCTAssertEqual(session.snapshot?.status,"failed");XCTAssertEqual(session.snapshot?.history.count,0)
    }
    func testAnswerAfterFirstResultIsRejectedWithoutSecondDispatch() async throws {
        let script=Script([#"{"type":"tool","name":"get_app_info","arguments":{}}"#,#"{"type":"answer","text":"skip models"}"#])
        let (_,session)=try await fixture(script);try approve(session);session.run();try await waitUntil { !session.isRunning }
        XCTAssertEqual(session.snapshot?.status,"failed");XCTAssertEqual(session.snapshot?.history.map(\.name),["get_app_info"])
        XCTAssertNil(session.snapshot?.answer)
    }
    func testAlteredQueryCannotDispatchAnUnapprovedMemorySearch() async throws {
        let script=Script([#"{"type":"tool","name":"search_memory","arguments":{"query":"Other","limit":2}}"#])
        let (_,session)=try await fixture(script)
        let scope=try LocalCompletionContract.parse(#"{"schema":1,"steps":[{"name":"search_memory","arguments":{"query":"Cedar","limit":2}}]}"#)
        session.prepareCompletion(goal:"Search saved memory",contract:scope)
        session.approveCompletion(goal:"Search saved memory",contract:scope);session.run()
        try await waitUntil { !session.isRunning }
        XCTAssertEqual(session.snapshot?.status,"failed");XCTAssertEqual(session.snapshot?.history.count,0)
    }
    func testStaleScopeProviderAndDiscardCannotCreateTask() async throws {
        let script=Script([]); let (model,session)=try await fixture(script)
        session.prepareCompletion(goal:"Inspect app and models",contract:try contract)
        session.approveCompletion(goal:"Changed",contract:try contract)
        XCTAssertTrue(session.records.isEmpty);XCTAssertNil(session.proposedCompletion)
        session.prepareCompletion(goal:"Inspect app and models",contract:try contract)
        model.selectedProviderID="missing"
        session.approveCompletion(goal:"Inspect app and models",contract:try contract)
        XCTAssertTrue(session.records.isEmpty);XCTAssertNil(session.proposedCompletion)
        model.selectedProviderID="completion-fixture"
        session.prepareCompletion(goal:"Inspect app and models",contract:try contract);session.discardReadPlan()
        session.approveCompletion(goal:"Inspect app and models",contract:try contract)
        XCTAssertTrue(session.records.isEmpty);XCTAssertEqual(script.requests.count,0)
    }
    func testCancellationDuringSuspendedDecisionCannotDispatchLateOutput() async throws {
        let script=Script([]);script.suspend=true
        let (_,session)=try await fixture(script);try approve(session);session.run()
        try await waitUntil { script.continuation != nil }
        session.stop(cancelTask:true)
        script.continuation?.yield(#"{"type":"tool","name":"get_app_info","arguments":{}}"#);script.continuation?.finish()
        try await waitUntil { !session.isRunning }
        XCTAssertEqual(session.snapshot?.status,"cancelled");XCTAssertEqual(session.snapshot?.history.count,0)
    }
    @MainActor private final class Script {
        var outputs:[String],requests:[GenerationRequest]=[],suspend=false
        var continuation:AsyncThrowingStream<String,Error>.Continuation?
        init(_ outputs:[String]) { self.outputs=outputs }
        func stream(_ request:GenerationRequest) async throws -> AsyncThrowingStream<String,Error> {
            requests.append(request)
            if suspend { return AsyncThrowingStream { continuation=$0 } }
            guard !outputs.isEmpty else { throw LocalAgentError.invalidState }
            let next=outputs.removeFirst()
            return AsyncThrowingStream { $0.yield(next);$0.finish() }
        }
    }
}
