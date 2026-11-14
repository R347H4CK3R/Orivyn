import XCTest
@testable import JarvisEVO
final class LocalAgentGrammarPolicyTests: XCTestCase {
    private let source = "root ::= tool | read-result | answer\ntool-body ::= search | read_conversation | calculate\nconversation-read ::= id ws string ws index\n"
    private let id = "abcdefab-1234-1234-1234-123456789abc"
    func testNoHitsRemovesOnlyConversationReadAlternative() throws {
        let grammar = try LocalAgentGrammar.constrain(source, requireTool: true, conversationIDs: [])
        XCTAssertTrue(grammar.hasPrefix("root ::= tool\n"))
        XCTAssertTrue(grammar.contains("tool-body ::= search | calculate\n"))
        XCTAssertFalse(grammar.contains("conversation-id ::="))
    }
    func testExactReturnedUUIDLiteralReplacesArbitraryString() throws {
        let grammar = try LocalAgentGrammar.constrain(source, requireTool: false, conversationIDs: [id])
        XCTAssertTrue(grammar.contains("tool-body ::= search | read_conversation | calculate"))
        XCTAssertTrue(grammar.contains("conversation-read ::= id ws conversation-id ws index"))
        XCTAssertTrue(grammar.contains("conversation-id ::= \"\\\"\(id)\\\"\""))
    }
    func testMalformedPolicyAndUnknownGrammarFailClosed() {
        for ids in [["saved_conversation_id"], ["1234567890"], [id.uppercased()], [id,id], Array(repeating:id,count:61), [id+"\nroot ::= answer"]] {
            XCTAssertThrowsError(try LocalAgentGrammar.constrain(source, requireTool: true, conversationIDs: ids))
        }
        XCTAssertThrowsError(try LocalAgentGrammar.constrain("unknown", requireTool: false, conversationIDs: []))
    }
    func testRequestCarriesOnlyExplicitCapabilitySet() {
        XCTAssertEqual(GenerationRequest.localAgent(prompt:"goal",requiresTool:true).localAgentConversationIDs, [])
        XCTAssertEqual(GenerationRequest.localAgent(prompt:"goal",requiresTool:false,conversationIDs:[id]).localAgentConversationIDs, [id])
    }
}
