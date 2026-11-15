import XCTest
@testable import JarvisEVO
final class LocalCompletionGrammarTests: XCTestCase {
    private let source = "root ::= tool | read-result | answer\ntool-body ::= search | read_conversation | calculate\nconversation-read ::= id ws string ws index\nanswer ::= string\n"
    func testExactNextActionOnlyAndFinalAnswerOnly() throws {
        let contract=try LocalCompletionContract.parse(#"{"schema":1,"steps":[{"name":"search_memory","arguments":{"query":"Cedar","limit":2}}]}"#)
        let policy=try LocalCompletionPolicy.derive(contract:contract,history:[])
        let grammar=try LocalAgentGrammar.completion(policy,source:source)
        XCTAssertTrue(grammar.hasPrefix("root ::= completion-next\n"))
        XCTAssertTrue(grammar.contains("search_memory")); XCTAssertTrue(grammar.contains("Cedar"))
        let done=LocalCompletionPolicy(actions:[],canAnswer:true)
        XCTAssertTrue(try LocalAgentGrammar.completion(done,source:source).hasPrefix("root ::= answer\n"))
    }
    func testInvalidPolicyCannotCreateBroaderGrammar() throws {
        let action=try LocalCompletionContract.Action(value:.object(["name":.string("list_models"),"arguments":.object([:])]))
        for policy in [LocalCompletionPolicy(actions:[],canAnswer:false),LocalCompletionPolicy(actions:[action,action],canAnswer:false),LocalCompletionPolicy(actions:[action],canAnswer:true)] {
            XCTAssertThrowsError(try LocalAgentGrammar.completion(policy,source:source))
        }
        XCTAssertThrowsError(try LocalAgentGrammar.completion(.init(actions:[],canAnswer:true),source:"unknown"))
    }
    func testRequestModeCannotMixWithGenericOrConversationMode() throws {
        let policy=LocalCompletionPolicy(actions:[],canAnswer:true)
        var request=GenerationRequest.completionAgent(prompt:"complete stored evidence",policy:policy)
        XCTAssertEqual(request.messages.first?.content,"complete stored evidence")
        XCTAssertEqual(request.localCompletionPolicy?.canAnswer,true)
        XCTAssertNil(request.localAgentRequiresTool); XCTAssertNil(request.localReadWorkflowPolicy)
        XCTAssertNoThrow(try request.validateInternalModes())
        request.localAgentRequiresTool=false
        XCTAssertThrowsError(try request.validateInternalModes())
    }
}
