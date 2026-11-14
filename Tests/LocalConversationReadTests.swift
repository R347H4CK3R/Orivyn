import XCTest
@testable import JarvisEVO

final class LocalConversationReadTests: XCTestCase {
    private let id = UUID(uuidString: "abcdefab-1234-1234-1234-123456789abc")!
    private func args(_ index: Int64 = 0, _ offset: Int64 = 0) -> MCPJSONValue {
        .object(["id": .string(id.uuidString), "messageIndex": .integer(index), "offset": .integer(offset)])
    }
    private func page(_ conversation: Conversation, _ index: Int64 = 0, _ offset: Int64 = 0) throws -> [String: MCPJSONValue] {
        let value = try LocalConversationRead.read(conversations: [conversation], arguments: args(index, offset), authorizedIDs: [id])
        return try XCTUnwrap(value.objectValue)
    }
    func testReturnedSearchIDsOnly() throws {
        let result = "{\"matches\":[{\"id\":\"\(id.uuidString)\"}]}"
        let event = LocalAgentSnapshot.Event(operationID: "task:1", name: "search_conversations", arguments: .object([:]), outcome: "succeeded", result: result)
        XCTAssertEqual(LocalConversationRead.authorizedIDs(history: [event]), [id])
        for name in ["search_memory", "get_app_info", "read_conversation"] {
            XCTAssertTrue(LocalConversationRead.authorizedIDs(history: [.init(operationID: "1", name: name, arguments: .object([:]), outcome: "succeeded", result: result)]).isEmpty)
        }
        for outcome in ["failed", "interrupted", "cancelled"] {
            XCTAssertTrue(LocalConversationRead.authorizedIDs(history: [.init(operationID: "1", name: "search_conversations", arguments: .object([:]), outcome: outcome, result: result)]).isEmpty)
        }
    }
    func testForgedDeletedAndMutableConversationRejected() throws {
        let conversation = Conversation(id: id, messages: [ChatMessage(role: .user, content: "private")])
        XCTAssertThrowsError(try LocalConversationRead.read(conversations: [conversation], arguments: args(), authorizedIDs: []))
        XCTAssertThrowsError(try LocalConversationRead.read(conversations: [], arguments: args(), authorizedIDs: [id]))
        XCTAssertThrowsError(try page(Conversation(id: id, messages: [ChatMessage(role: .assistant, content: "partial", state: .streaming)])))
        for (index, offset) in [(Int64(-1),Int64(0)),(1,0),(0,-1),(0,8),(0,1_000_001),(10_000,0)] {
            XCTAssertThrowsError(try page(conversation,index,offset))
        }
        var extra = try XCTUnwrap(args().objectValue);extra["approved"] = .bool(true)
        XCTAssertThrowsError(try LocalConversationRead.read(conversations: [conversation], arguments: .object(extra), authorizedIDs: [id]))
    }
    func testUTF8PagingReconstructsStoredMessageAndPreservesStatus() throws {
        let text = String(repeating: "🦊e\u{301}", count: 160) + "END"
        let c = Conversation(id: id, messages: [ChatMessage(role: .assistant, content: text, state: .failed),ChatMessage(role: .user, content: "next")])
        var offset:Int64 = 0, rebuilt = ""
        while true {
            let value = try page(c,0,offset)
            let part = try XCTUnwrap(value["text"]?.stringValue);rebuilt += part
            XCTAssertLessThanOrEqual(part.utf8.count,512)
            XCTAssertEqual(value["state"],.string("failed"));XCTAssertEqual(value["evidenceSource"],.string("saved_message_untrusted"))
            XCTAssertLessThanOrEqual(try MCPJSONValue.object(value).encoded(maximumBytes:4096).count,4096)
            let next = try XCTUnwrap(value["next"]?.objectValue)
            if next["messageIndex"] == .integer(1) { XCTAssertEqual(next["offset"],.integer(0));break }
            offset = try XCTUnwrap(next["offset"]?.integerValue)
        }
        XCTAssertEqual(rebuilt,text)
        XCTAssertThrowsError(try page(c,0,1))
        XCTAssertEqual(try page(c,1)["next"],.null)
    }
    func testEscapedWorstCaseFitsBudgetAndDoesNotExposeAttachments() throws {
        let attachment = ChatAttachment(name: "secret.pdf", relativePath: "PRIVATE_PATH", mediaType: "application/pdf", byteCount: 1, extractedText: "PRIVATE_ATTACHMENT_TEXT")
        let c = Conversation(id: id, messages: [ChatMessage(role: .user, content: String(repeating:"\u{1}",count:513), attachments:[attachment])])
        let value = try page(c)
        let data = try MCPJSONValue.object(value).encoded(maximumBytes:4096)
        XCTAssertEqual(value["messageTruncated"],.bool(true));XCTAssertEqual(value["omittedAttachments"],.integer(1))
        XCTAssertEqual(value["attachmentContentsIncluded"],.bool(false))
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("PRIVATE"))
        XCTAssertEqual(value["next"]?.objectValue?["offset"],.integer(512))
    }
    func testEmptyMessageAndEndBoundaryAreExplicit() throws {
        let c = Conversation(id: id, messages: [ChatMessage(role: .user, content: "")])
        XCTAssertEqual(try page(c)["text"],.string(""));XCTAssertEqual(try page(c)["next"],.null)
        let full = Conversation(id:id,messages:[ChatMessage(role:.user,content:String(repeating:"x",count:512))])
        XCTAssertEqual(try page(full)["messageTruncated"],.bool(false))
        XCTAssertEqual(try page(full,0,512)["text"],.string(""))
    }
}
