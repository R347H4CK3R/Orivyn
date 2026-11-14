import Foundation

actor FixtureProvider: AIProvider {
    nonisolated let id: String
    nonisolated let displayName = "Unit-test provider"
    let response: String?
    init(_ id:String="fixture",response:String?) { self.id=id;self.response=response }
    func stream(_ request: GenerationRequest) async throws -> AsyncThrowingStream<String,Error> {
        guard request.localReadPlanProposal,request.localAgentRequiresTool==nil else { throw LocalAgentError.invalidState }
        guard let response else { while true { try await Task.sleep(for:.milliseconds(5)) } }
        return AsyncThrowingStream { $0.yield(response);$0.finish() }
    }
}
@MainActor final class AppModel {
    var provider:(any AIProvider)?
    var selectedLocalAgentProvider:(any AIProvider)? { provider }
    var heavyWorkLease:LocalHeavyWorkLease?
    var finishDelay=false
    var sourceReads=0
    var conversations:[Conversation] { sourceReads += 1; return [] }
    var installedModels:[LocalModelDescriptor]=[]
    var memories:[MemoryNote]=[]
    func beginHeavyWork(id:UUID,kind:LocalHeavyWorkKind) async throws { guard heavyWorkLease==nil else { throw LocalAgentError.staleOwner };heavyWorkLease = .init(id:id,kind:kind,phase:.ready) }
    func finishLocalAgentWork(id:UUID) async { if finishDelay { try? await Task.sleep(for:.milliseconds(100)) };if heavyWorkLease?.id==id { heavyWorkLease=nil } }
}
@MainActor final class LocalAgentCore {
    init() throws {}
    func call(_ name:String,_ args:[String]) throws -> String { try ReviewedSessionOwnershipSmoke.core(name,args) }
    func snapshot(_ raw:String) throws -> LocalAgentSnapshot { try JSONDecoder().decode(LocalAgentSnapshot.self,from:Data(raw.utf8)) }
}
@main struct ReviewedSessionOwnershipSmoke {
    static func core(_ name:String,_ args:[String]) throws -> String {
        let root=URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent(),process=Process(),input=Pipe(),output=Pipe()
        process.executableURL=URL(fileURLWithPath:ProcessInfo.processInfo.environment["ORIVYN_TEST_NODE"]!)
        process.arguments=[root.appendingPathComponent("CalculatorAgentCore.cjs").path];process.standardInput=input;process.standardOutput=output
        try process.run();input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject:["method":name,"args":args]));try input.fileHandleForWriting.close()
        let bytes=output.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        guard process.terminationStatus==0 else { throw LocalAgentError.invalidState }
        return try JSONDecoder().decode(String.self,from:bytes)
    }
    @MainActor static func wait(_ condition:()->Bool) async throws { for _ in 0..<3000 { if condition(){return};try await Task.sleep(for:.milliseconds(1)) };throw LocalAgentError.staleOwner }
    @MainActor static func main() async throws {
        let model=AppModel(),directory=URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("records"),session=try LocalAgentSession(model:model,directory:directory)
        session.create(goal:"Existing task");let old=session.snapshot!.id
        model.provider=FixtureProvider(response:nil);session.prepareReadPlan(goal:"Read Notes second message",kind:"conversation_read")
        session.stop(cancelTask:true);try await wait { !session.isRunning }
        precondition(session.snapshot?.id==old && session.snapshot?.status=="ready" && model.heavyWorkLease==nil)
        model.provider=FixtureProvider(response:"invalid");session.prepareReadPlan(goal:"Read Notes second message",kind:"conversation_read");try await wait { !session.isRunning }
        precondition(session.snapshot?.id==old && session.snapshot?.status=="ready" && session.proposedReadPlan==nil)
        model.provider=FixtureProvider(response:#"{"schema":1,"kind":"conversation_search","query":"Notes"}"#)
        session.prepareReadPlan(goal:"Read Notes",kind:"conversation_read");try await wait { !session.isRunning }
        precondition(session.proposedReadPlan==nil && session.snapshot?.id==old)
        let valid=#"{"schema":1,"kind":"conversation_read","query":"Notes","title":"Notes","messageIndexes":[1]}"#
        model.provider=FixtureProvider(response:valid);model.finishDelay=true;session.prepareReadPlan(goal:"Original goal",kind:"conversation_read")
        try await wait { session.proposedReadPlan != nil };session.stop(cancelTask:true);try await wait { !session.isRunning }
        precondition(session.proposedReadPlan==nil && session.snapshot?.id==old && session.snapshot?.status=="ready")
        model.finishDelay=false;session.prepareReadPlan(goal:"Original goal",kind:"conversation_read");try await wait { !session.isRunning }
        session.run();precondition(!session.isRunning && session.snapshot?.id==old)
        model.provider=FixtureProvider("different",response:valid);session.approveReadPlan();precondition(session.snapshot?.id==old)
        session.discardReadPlan();precondition(session.proposedReadPlan==nil)
        session.prepareReadPlan(goal:"Immutable reviewed goal",kind:"conversation_read");try await wait { !session.isRunning };session.approveReadPlan()
        precondition(session.snapshot?.id != old && session.snapshot?.goal=="Immutable reviewed goal" && session.snapshot?.status=="ready" && session.snapshot?.readPlan?.messageIndexes==[1])
        precondition(session.snapshot?.history.isEmpty==true && model.sourceReads==0)
        print("PASS production session draft cancellation, teardown cancellation, parse failure, stale provider, review/run separation, immutable goal and zero source reads before explicit Run (Linux Node bridge/unit provider; not iOS/model quality)")
    }
}
