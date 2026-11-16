import XCTest
@testable import JarvisEVO

final class ChatGPTConversationRestoreTests: XCTestCase {
    let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    func record() -> [String: Any] {
        ["id": conversationID.uuidString, "title": "Restored", "create_time": 100.0, "update_time": 200.0,
         "current_node": "leaf", "mapping": ["leaf": ["parent": NSNull(), "message": ["id": messageID.uuidString, "create_time": 150.0, "author": ["role": "user"], "content": ["content_type": "text", "parts": ["Saved question"]]]]]]
    }
    func testConvertsIntoContinuableConversationInsteadOfMemoryExcerpts() throws {
        let data = try JSONSerialization.data(withJSONObject: record())
        let result = try ChatGPTConversationRestore.convert(data, identities: [:])
        XCTAssertEqual(result.conversation?.id, conversationID)
        XCTAssertEqual(result.conversation?.messages.first?.id, messageID)
        XCTAssertEqual(result.conversation?.messages.first?.content, "Saved question")
        XCTAssertEqual(result.conversation?.messages.first?.createdAt, Date(timeIntervalSince1970: 150))
        XCTAssertEqual(result.conversation?.messages.first?.state, .complete)
        XCTAssertEqual(result.omittedMessages, 0)
    }

    func testRejectsInvalidAndOversizedRecords() throws {
        for data in [Data("[]".utf8), Data("{}".utf8), Data(repeating: 32, count: 16_000_001)] {
            XCTAssertThrowsError(try ChatGPTConversationRestore.convert(data, identities: [:]))
        }
    }
    func testSelectedBranchExcludesAlternativeAndHiddenAssistantMessages() throws {
        var value = record()
        var mapping = value["mapping"] as! [String: [String: Any]]
        var alternative = mapping["leaf"]!
        var hidden = alternative["message"] as! [String: Any]
        hidden["id"] = UUID().uuidString
        hidden["author"] = ["role": "assistant"]
        hidden["channel"] = "analysis"
        alternative["message"] = hidden
        mapping["hidden"] = alternative
        mapping["leaf"]!["parent"] = "hidden"
        mapping["unused"] = alternative
        value["mapping"] = mapping
        let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:])
        XCTAssertEqual(result.conversation?.messages.count, 1)
        XCTAssertEqual(result.omittedMessages, 2)
    }
    func testRejectsCyclicOrMissingAncestry() throws {
        for parent in ["leaf", "absent"] {
            var value = record()
            var mapping = value["mapping"] as! [String: [String: Any]]
            mapping["leaf"]!["parent"] = parent
            value["mapping"] = mapping
            XCTAssertThrowsError(try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:]))
        }
    }
    func testNonUUIDIdentityRequiresCallerOwnedDurableMapping() throws {
        var value = record(); value["id"] = "legacy-conversation"
        let data = try JSONSerialization.data(withJSONObject: value)
        XCTAssertThrowsError(try ChatGPTConversationRestore.convert(data, identities: [:]))
        let result = try ChatGPTConversationRestore.convert(data, identities: ["conversation:legacy-conversation": conversationID])
        XCTAssertEqual(result.conversation?.id, conversationID)
    }
    func testDoNotRememberContentIsNotActivated() throws {
        var value = record(); value["is_do_not_remember"] = true
        let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:])
        XCTAssertNil(result.conversation)
        XCTAssertEqual(result.omittedMessages, 1)
    }
    func testMissingTimestampFailsInsteadOfPretendingItHappenedNow() throws {
        var value = record(); value.removeValue(forKey: "create_time")
        XCTAssertThrowsError(try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:]))
    }

    func testIncompleteAssistantIsNotMarkedComplete() throws {
        var value = record()
        var mapping = value["mapping"] as! [String: [String: Any]]
        var message = mapping["leaf"]!["message"] as! [String: Any]
        message["author"] = ["role": "assistant"]
        for (status, expected) in [("in_progress", MessageState.interrupted), ("failed", .failed), ("finished_successfully", .complete)] {
            message["status"] = status; mapping["leaf"]!["message"] = message; value["mapping"] = mapping
            let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:])
            XCTAssertEqual(result.conversation?.messages.first?.state, expected)
        }
    }

    func testUnresolvedMediaIsRetainedAndAccountedWithoutInventingAttachmentPaths() throws {
        var value = record()
        var mapping = value["mapping"] as! [String: [String: Any]]
        var message = mapping["leaf"]!["message"] as! [String: Any]
        message["content"] = ["content_type": "multimodal_text", "parts": ["Picture", ["asset_pointer": "sediment://synthetic-asset"]]] as [String: Any]
        message["metadata"] = ["attachments": [["id": "synthetic-document"]]]
        mapping["leaf"]!["message"] = message; value["mapping"] = mapping
        let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:])
        XCTAssertEqual(result.unresolvedContent.count, 2)
        XCTAssertEqual(result.unresolvedContent.first?.messageID, messageID)
        XCTAssertTrue(result.conversation!.messages[0].attachments.isEmpty)
        XCTAssertEqual(result.conversation!.messages[0].content, "Picture")
    }

    func testMediaOnlyMessageKeepsUnresolvedReference() throws {
        var value = record()
        var mapping = value["mapping"] as! [String: [String: Any]]
        var message = mapping["leaf"]!["message"] as! [String: Any]
        message["content"] = ["content_type": "multimodal_text", "parts": [["asset_pointer": "sediment://synthetic"]]]
        mapping["leaf"]!["message"] = message; value["mapping"] = mapping
        let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:])
        XCTAssertEqual(result.unresolvedContent.count, 1)
        XCTAssertEqual(result.conversation?.messages.count, 1)
        XCTAssertEqual(result.conversation?.messages.first?.content, "")
    }
    func testBooleanTimestampRejected() throws {
        var value = record(); value["create_time"] = true
        XCTAssertThrowsError(try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:]))
    }
    func testSystemToolAndPrivateMessagesAreNotActivated() throws {
        for (role, metadata) in [("system", [:]), ("tool", [:]), ("user", ["is_do_not_remember": true]), ("assistant", ["is_visually_hidden_from_conversation": true])] {
            var value = record()
            var mapping = value["mapping"] as! [String: [String: Any]]
            var message = mapping["leaf"]!["message"] as! [String: Any]
            message["author"] = ["role": role]; message["metadata"] = metadata
            mapping["leaf"]!["message"] = message; value["mapping"] = mapping
            let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:])
            XCTAssertEqual(result.conversation?.messages.count, 0)
            XCTAssertEqual(result.omittedMessages, 1)
        }
    }

    func testUnresolvedContentCountIsBoundedBeforeAllocatingOutput() throws {
        var value = record()
        var mapping = value["mapping"] as! [String: [String: Any]]
        var message = mapping["leaf"]!["message"] as! [String: Any]
        message["content"] = ["content_type": "multimodal_text", "parts": Array(repeating: NSNull(), count: 2049)]
        mapping["leaf"]!["message"] = message; value["mapping"] = mapping
        XCTAssertThrowsError(try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:]))
    }
}
