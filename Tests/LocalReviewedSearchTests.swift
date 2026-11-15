import XCTest
@testable import JarvisEVO
final class LocalReviewedSearchTests: XCTestCase {
    func testSearchOnlyCannotAnswerFromDeletedChangedOrForgedSearchEvidence() throws {
        let plan=try LocalReadPlan.parse(#"{"schema":1,"kind":"conversation_search","query":"Notes"}"#)
        let original=Conversation(title:"Notes",messages:[ChatMessage(role:.user,content:"original")])
        let value=try LocalReviewedSearch.result(plan:plan,conversations:[original])
        func event(_ result:MCPJSONValue) throws -> LocalAgentSnapshot.Event {
            try JSONDecoder().decode(LocalAgentSnapshot.Event.self,from:MCPJSONValue.object(["operationID":.string("fixture:1"),"name":.string("search_conversations"),"arguments":.object(["query":.string("Notes"),"limit":.integer(10)]),"outcome":.string("succeeded"),"result":.string(String(decoding:result.encoded(),as:UTF8.self))]).encoded())
        }
        let history=[try event(value)]
        XCTAssertTrue(try LocalReadWorkflowPolicy.derive(plan:plan,history:history,conversations:[original]).canAnswer)
        XCTAssertThrowsError(try LocalReadWorkflowPolicy.derive(plan:plan,history:history,conversations:[]))
        var changed=original;changed.title="Notes changed"
        XCTAssertThrowsError(try LocalReadWorkflowPolicy.derive(plan:plan,history:history,conversations:[changed]))
        var corrupt=value.objectValue!;corrupt["matches"] = .array([])
        XCTAssertThrowsError(try LocalReadWorkflowPolicy.derive(plan:plan,history:[event(.object(corrupt))],conversations:[original]))
    }
}
