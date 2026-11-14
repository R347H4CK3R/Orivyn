import XCTest
@testable import JarvisEVO
final class LocalReadPlanTests: XCTestCase {
    func testStrictPlanRejectsDuplicatesUnknownFieldsAndUnboundedReads() throws {
        let valid = #"{"schema":1,"kind":"conversation_read","query":"Notes","title":"Notes","messageIndexes":[1]}"#
        XCTAssertEqual(try LocalReadPlan.parse(valid).messageIndexes,[1])
        for bad in [valid.replacingOccurrences(of:"\"schema\":1",with:"\"schema\":1,\"schema\":1"),valid.replacingOccurrences(of:"[1]",with:"[1,1]"),valid.replacingOccurrences(of:"[1]",with:"[]"),valid.replacingOccurrences(of:"[1]",with:"[0,1,2,3]"),valid.replacingOccurrences(of:"\"schema\":1",with:"\"extra\":true,\"schema\":1")] { XCTAssertThrowsError(try LocalReadPlan.parse(bad)) }
    }
    func testSearchOnlyHasNoReadScope() throws {
        let plan = try LocalReadPlan.parse(#"{"schema":1,"kind":"conversation_search","query":"Notes"}"#)
        XCTAssertNil(plan.title); XCTAssertNil(plan.messageIndexes)
        XCTAssertThrowsError(try LocalReadPlan.parse(#"{"schema":1,"kind":"conversation_search","query":"Notes","title":"Notes"}"#))
    }
}

final class LocalReadWorkflowPolicyTests: XCTestCase {
    let id = UUID(uuidString:"abcdefab-1234-1234-1234-123456789abc")!
    func plan() throws -> LocalReadPlan { try .parse(#"{"schema":1,"kind":"conversation_read","query":"Notes","title":"Notes","messageIndexes":[1]}"#) }
    func event(_ name: String, _ arguments: MCPJSONValue, _ result: MCPJSONValue, step: Int) throws -> LocalAgentSnapshot.Event {
        let value: MCPJSONValue = .object(["operationID":.string("test:\(step)"),"name":.string(name),"arguments":arguments,"outcome":.string("succeeded"),"result":.string(String(decoding:try result.encoded(),as:UTF8.self))])
        return try JSONDecoder().decode(LocalAgentSnapshot.Event.self,from:value.encoded())
    }
    func testIndependentGuardRequiresReadAndRejectsChangedOrRenamedSource() throws {
        var c = Conversation(id:id,title:"Notes",messages:[ChatMessage(role:.user,content:"first"),ChatMessage(role:.assistant,content:"actual second")])
        let searchArgs:MCPJSONValue = .object(["query":.string("Notes"),"limit":.integer(10)])
        let result = try LocalReviewedSearch.result(plan:plan(),conversations:[c])
        var history = [try event("search_conversations",searchArgs,result,step:1)]
        let incomplete = try LocalReadWorkflowPolicy.derive(plan:plan(),history:history,conversations:[c])
        XCTAssertFalse(incomplete.canAnswer); XCTAssertEqual(incomplete.actions.count,1)
        let action = incomplete.actions[0]
        let page = try LocalConversationRead.read(conversations:[c],arguments:action.arguments,authorizedIDs:[id])
        history.append(try event(action.name,action.arguments,page,step:2))
        XCTAssertTrue(try LocalReadWorkflowPolicy.derive(plan:plan(),history:history,conversations:[c]).canAnswer)
        c.messages[1].content = "changed second"
        XCTAssertThrowsError(try LocalReadWorkflowPolicy.derive(plan:plan(),history:history,conversations:[c]))
        c.messages[1].content = "actual second"; c.title = "renamed"
        XCTAssertThrowsError(try LocalReadWorkflowPolicy.derive(plan:plan(),history:history,conversations:[c]))
    }
}
final class LocalReadRequestModeTests: XCTestCase {
    func testProposalAndReviewedModesNeverCombineWithOtherExecutionModes() throws {
        let proposal = try GenerationRequest.readPlanProposal(goal:"Read second note",kind:"conversation_read")
        XCTAssertNoThrow(try proposal.validateInternalModes())
        XCTAssertTrue(proposal.localReadPlanProposal); XCTAssertNil(proposal.localAgentRequiresTool)
        for mode in 0..<3 {
            var conflict=proposal
            if mode==0 { conflict.nativeReadGoal="read" }
            if mode==1 { conflict.localAgentRequiresTool=true }
            if mode==2 { conflict.localReadWorkflowPolicy = .init(actions:[],canAnswer:true) }
            XCTAssertThrowsError(try conflict.validateInternalModes())
        }
    }
}
final class ReviewedLongTitleTests: XCTestCase {
    func testFullTitleMetadataDoesNotSelectSameClippedPrefix() throws {
        let prefix=String(repeating:"x",count:96), a=Conversation(title:prefix+" alpha",messages:[]), b=Conversation(title:prefix+" beta",messages:[])
        let matches:[MCPJSONValue] = [a,b].map { .object(["id":.string($0.id.uuidString),"title":.string(prefix)]) }
        XCTAssertEqual(try LocalReadWorkflowPolicy.fullTitleMatchIDs(matches:matches,title:b.title,conversations:[a,b]),[b.id.uuidString.lowercased()])
        XCTAssertEqual(try LocalReadWorkflowPolicy.fullTitleMatchIDs(matches:matches,title:prefix,conversations:[a,b]),[])
    }
}

final class ExplicitReadPlanKindTests: XCTestCase {
    func testUserSelectedKindIsRequiredAndGrammarRejectsOtherShape() throws {
        XCTAssertThrowsError(try GenerationRequest.readPlanProposal(goal:"Read Notes",kind:"send"))
        for kind in ["conversation_read","conversation_search"] {
            let request=try GenerationRequest.readPlanProposal(goal:"Read Notes",kind:kind)
            XCTAssertEqual(request.localReadPlanKind,kind)
            let grammar=try LocalAgentGrammar.readPlanProposal(kind:kind)
            XCTAssertTrue(grammar.components(separatedBy:"\n")[0].contains(kind=="conversation_read" ? "(read)" : "(search)"))
        }
    }
}
final class NativeReviewedPaginationTests: XCTestCase {
    func testNativeRequiresContiguousCompleteUnicodePagesAndRejectsChangedPrefix() throws {
        let plan=try LocalReadPlan.parse(#"{"schema":1,"kind":"conversation_read","query":"Pages","title":"Pages","messageIndexes":[0]}"#)
        var conversation=Conversation(title:"Pages",messages:[ChatMessage(role:.user,content:String(repeating:"é",count:300))])
        func event(_ action:LocalReadWorkflowPolicy.Action,_ result:MCPJSONValue,_ step:Int) throws -> LocalAgentSnapshot.Event {
            try JSONDecoder().decode(LocalAgentSnapshot.Event.self,from:MCPJSONValue.object(["operationID":.string("page:\(step)"),"name":.string(action.name),"arguments":action.arguments,"outcome":.string("succeeded"),"result":.string(String(decoding:result.encoded(),as:UTF8.self))]).encoded())
        }
        let initial=try LocalReadWorkflowPolicy.derive(plan:plan,history:[],conversations:[conversation])
        var history=[try event(initial.actions[0],LocalReviewedSearch.result(plan:plan,conversations:[conversation]),1)]
        let first=try LocalReadWorkflowPolicy.derive(plan:plan,history:history,conversations:[conversation]).actions[0]
        history.append(try event(first,LocalConversationRead.read(conversations:[conversation],arguments:first.arguments,authorizedIDs:[conversation.id]),2))
        let partial=try LocalReadWorkflowPolicy.derive(plan:plan,history:history,conversations:[conversation])
        XCTAssertFalse(partial.canAnswer);XCTAssertEqual(partial.actions[0].arguments.objectValue?["offset"]?.integerValue,512)
        let last=partial.actions[0]
        history.append(try event(last,LocalConversationRead.read(conversations:[conversation],arguments:last.arguments,authorizedIDs:[conversation.id]),3))
        XCTAssertTrue(try LocalReadWorkflowPolicy.derive(plan:plan,history:history,conversations:[conversation]).canAnswer)
        conversation.messages[0].content="ø"+String(repeating:"é",count:299)
        XCTAssertThrowsError(try LocalReadWorkflowPolicy.derive(plan:plan,history:history,conversations:[conversation]))
    }
}
