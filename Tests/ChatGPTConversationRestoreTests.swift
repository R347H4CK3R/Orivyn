import XCTest
@testable import JarvisEVO

final class ChatGPTConversationRestoreTests: XCTestCase {
    let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    func record() -> [String: Any] {
        ["id": conversationID.uuidString, "title": "Restored", "create_time": 100.0, "update_time": 200.0,
         "current_node": "leaf", "mapping": ["leaf": ["parent": NSNull(), "message": ["id": messageID.uuidString, "create_time": 150.0, "author": ["role": "user"], "content": ["content_type": "text", "parts": ["Saved question"]]]]]]
    }
    func testRestoresVisibleStructuredCodeTextWithoutExecution() throws {
        var value = record()
        var mapping = value["mapping"] as! [String: [String: Any]]
        var message = mapping["leaf"]!["message"] as! [String: Any]
        message["author"] = ["role": "assistant"]
        message["channel"] = "final"; message["recipient"] = "all"
        message["status"] = "finished_successfully"
        message["content"] = ["content_type": "code", "language": "python", "text": "print('synthetic')"]
        mapping["leaf"]!["message"] = message; value["mapping"] = mapping
        let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:])
        XCTAssertEqual(result.conversation?.messages.map(\.content), ["print('synthetic')"])
        XCTAssertEqual(result.conversation?.messages.first?.state, .complete)
        XCTAssertEqual(result.omittedMessages, 0)
    }
    func testStructuredCodeRetainsPrivacyRoutingAndStrictTextShape() throws {
        let variants: [[String: Any]] = [
            ["channel": "analysis"], ["recipient": "python"],
            ["metadata": ["is_visually_hidden_from_conversation": true]],
            ["metadata": ["is_do_not_remember": true]],
            ["metadata": ["is_user_system_message": true]],
            ["author": ["role": "tool"]],
            ["content": ["content_type": "code", "text": ["untrusted": "not text"]]],
            ["content": ["content_type": "unknown", "text": "not supported"]],
            ["content": ["content_type": "code", "text": NSNull(), "parts": ["do not infer"]]]
        ]
        for changes in variants {
            var value = record()
            var mapping = value["mapping"] as! [String: [String: Any]]
            var message = mapping["leaf"]!["message"] as! [String: Any]
            message["author"] = ["role": "assistant"]
            message["channel"] = "final"; message["recipient"] = "all"
            message["content"] = ["content_type": "code", "text": "private synthetic"]
            for (key, item) in changes { message[key] = item }
            mapping["leaf"]!["message"] = message; value["mapping"] = mapping
            let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:])
            XCTAssertEqual(result.conversation?.messages.count, 0)
            XCTAssertEqual(result.omittedMessages, 1)
            XCTAssertTrue(result.unresolvedContent.isEmpty)
        }
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

    func testNullAssistantRoutingFieldsMatchAbsentFields() throws {
        for channel: Any? in [nil, NSNull(), "final"] {
            for recipient: Any? in [nil, NSNull(), "all"] {
                var value = record()
                var mapping = value["mapping"] as! [String: [String: Any]]
                var message = mapping["leaf"]!["message"] as! [String: Any]
                message["author"] = ["role": "assistant"]
                message["status"] = "finished_successfully"
                message["channel"] = channel
                message["recipient"] = recipient
                mapping["leaf"]!["message"] = message
                value["mapping"] = mapping
                let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:])
                XCTAssertEqual(result.conversation?.messages.map(\.content), ["Saved question"])
                XCTAssertEqual(result.conversation?.messages.first?.state, .complete)
                XCTAssertEqual(result.omittedMessages, 0)
            }
        }
    }

    func testNullRoutingDoesNotExposeInternalOrMalformedAssistantMessages() throws {
        let cases: [(Any, Any)] = [("analysis", NSNull()), ("commentary", NSNull()),
            (NSNull(), "python"), (true, NSNull()), (NSNull(), 1), ("", "all"), ("final", "")]
        for (channel, recipient) in cases {
            var value = record()
            var mapping = value["mapping"] as! [String: [String: Any]]
            var message = mapping["leaf"]!["message"] as! [String: Any]
            message["author"] = ["role": "assistant"]
            message["channel"] = channel; message["recipient"] = recipient
            mapping["leaf"]!["message"] = message; value["mapping"] = mapping
            let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:])
            XCTAssertEqual(result.conversation?.messages.count, 0)
            XCTAssertEqual(result.omittedMessages, 1)
        }
    }

    func testNullRoutingDoesNotExposeHiddenOrPrivateAssistantMessages() throws {
        for flag in ["is_visually_hidden_from_conversation", "is_user_system_message", "is_do_not_remember"] {
            var value = record()
            var mapping = value["mapping"] as! [String: [String: Any]]
            var message = mapping["leaf"]!["message"] as! [String: Any]
            message["author"] = ["role": "assistant"]
            message["channel"] = NSNull(); message["recipient"] = NSNull()
            message["metadata"] = [flag: true]
            mapping["leaf"]!["message"] = message; value["mapping"] = mapping
            let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: [:])
            XCTAssertEqual(result.conversation?.messages.count, 0)
            XCTAssertEqual(result.omittedMessages, 1)
        }
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

    func testLegacyMessageTupleDoesNotAliasAcrossConversations() throws {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let mappings = ["conversation:a:b": conversationID, "conversation:a": conversationID,
                        "message:v1:3:a:b:1:c": firstID, "message:v1:1:a:3:b:c": secondID]
        for (conversation, messageID, expected) in [("a:b", "c", firstID), ("a", "b:c", secondID)] {
            var value = record(); value["id"] = conversation
            var nodes = value["mapping"] as! [String: [String: Any]]
            var message = nodes["leaf"]!["message"] as! [String: Any]
            message["id"] = messageID; nodes["leaf"]!["message"] = message; value["mapping"] = nodes
            let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: value), identities: mappings)
            XCTAssertEqual(result.conversation?.messages.first?.id, expected)
        }
    }
    func testFullyEscapedLongPrivacyKeysAreNotDropped() throws {
        let key = "is_visually_hidden_from_conversation"
        let escaped = key.utf8.map { String(format: "\\u%04x", $0) }.joined()
        var r = record(), nodes = rMapping(r), message = rMessage(r)
        message["metadata"] = [key: true]; nodes["leaf"]!["message"] = message; r["mapping"] = nodes
        let source = String(data: try JSONSerialization.data(withJSONObject: r), encoding: .utf8)!
            .replacingOccurrences(of: "\"" + key + "\"", with: "\"" + escaped + "\"")
        let result = try ChatGPTConversationRestore.convert(Data(source.utf8), identities: [:])
        XCTAssertEqual(result.conversation?.messages.count, 0)
        let duplicate = source.replacingOccurrences(of: "\"" + escaped + "\":true",
            with: "\"" + key + "\":false,\"" + escaped + "\":true")
        XCTAssertNotEqual(duplicate, source)
        XCTAssertThrowsError(try ChatGPTRecordProjection.project(Data(duplicate.utf8)))
    }

    func testProjectionMatchesLegacyConversionAcrossPrivacyRoutingAndOpaqueShapes() throws {
        let scalars: [Any] = [NSNull(), true, false, 0, 1, 2, "", "final", "analysis", "all", [], ["x": 1]]
        var fixtures: [[String: Any]] = [record()]
        for key in ["is_do_not_remember", "is_archived", "create_time", "update_time", "title", "current_node"] {
            for v in scalars { var r = record(); r[key] = v; fixtures.append(r) }
        }
        for key in ["channel", "recipient", "is_do_not_remember", "status", "create_time", "author", "content", "metadata"] {
            for v in scalars {
                var r = record(), nodes = rMapping(r), message = rMessage(r)
                message["author"] = ["role": "assistant"]; message[key] = v
                nodes["leaf"]!["message"] = message; r["mapping"] = nodes; fixtures.append(r)
            }
        }
        for key in ["is_do_not_remember", "is_visually_hidden_from_conversation", "is_user_system_message", "attachments"] {
            for v in scalars {
                var r = record(), nodes = rMapping(r), message = rMessage(r)
                message["metadata"] = [key: v]; nodes["leaf"]!["message"] = message; r["mapping"] = nodes; fixtures.append(r)
                var root = record(); root["metadata"] = [key: v]; fixtures.append(root)
            }
        }
        for parts: [Any] in [["text", NSNull(), true, 1, ["nested": ["x", 2, false]]],
                             ["", ["asset_pointer": "sediment://synthetic", "number": 1.25]], []] {
            var r = record(), nodes = rMapping(r), message = rMessage(r)
            message["content"] = ["content_type": "multimodal_text", "parts": parts]
            message["metadata"] = ["attachments": [NSNull(), ["id": "synthetic", "n": 1.25]]]
            nodes["leaf"]!["message"] = message; r["mapping"] = nodes; fixtures.append(r)
        }
        for (index, fixture) in fixtures.enumerated() {
            let data = try JSONSerialization.data(withJSONObject: fixture)
            let old = Result { try LegacyChatGPTConversationRestore.convert(data, identities: [:]) }
            let new = Result { try ChatGPTConversationRestore.convert(data, identities: [:]) }
            switch (old, new) {
            case (.success(let a), .success(let b)):
                XCTAssertEqual(a.conversation, b.conversation, "fixture \(index)")
                XCTAssertEqual(a.omittedMessages, b.omittedMessages, "fixture \(index)")
                XCTAssertEqual(a.unresolvedContent.map(\.originalJSON), b.unresolvedContent.map(\.originalJSON), "fixture \(index)")
                XCTAssertEqual(a.unresolvedContent.map(\.source), b.unresolvedContent.map(\.source), "fixture \(index)")
                XCTAssertEqual(a.unresolvedContent.map(\.messageID), b.unresolvedContent.map(\.messageID), "fixture \(index)")
            case (.failure, .failure): break
            default: XCTFail("Legacy differential mismatch at fixture \(index): \(old) / \(new)")
            }
        }
    }
    private func rMapping(_ r: [String: Any]) -> [String: [String: Any]] { r["mapping"] as! [String: [String: Any]] }
    private func rMessage(_ r: [String: Any]) -> [String: Any] { rMapping(r)["leaf"]!["message"] as! [String: Any] }

    func testUnusedRootMetadataAttachmentsAreSkippedWithoutOpaqueBudget() throws {
        var r = record()
        r["metadata"] = ["attachments": [["many": Array(repeating: 1, count: 20_001)]],
                         "is_visually_hidden_from_conversation": true,
                         "is_user_system_message": true] as [String: Any]
        let result = try ChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: r), identities: [:])
        XCTAssertEqual(result.conversation?.messages.map(\.content), ["Saved question"])
    }

    func testDenseUnknownMetadataIsSkippedAndSelectedDataRemainsExact() throws {
        var r = record()
        r["unused_metadata"] = Array(repeating: ["a": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "b": 1, "c": false] as [String: Any], count: 25_000)
        let data = try JSONSerialization.data(withJSONObject: r)
        let projected = try ChatGPTRecordProjection.project(data)
        XCTAssertNil(projected["unused_metadata"])
        let a = try ChatGPTConversationRestore.convert(projected: projected, identities: [:])
        let b = try LegacyChatGPTConversationRestore.convert(JSONSerialization.data(withJSONObject: record()), identities: [:])
        XCTAssertEqual(a.conversation, b.conversation)
    }
    func testOpaqueComplexityAndByteBudgetsRejectWithoutMaterializingWholeSubtree() throws {
        var r = record(), nodes = rMapping(r), message = rMessage(r)
        message["content"] = ["content_type": "multimodal_text", "parts": [["many": Array(repeating: 1, count: 20_001)]]]
        nodes["leaf"]!["message"] = message; r["mapping"] = nodes
        XCTAssertThrowsError(try ChatGPTRecordProjection.project(JSONSerialization.data(withJSONObject: r)))
        message["content"] = ["content_type": "multimodal_text", "parts": [["huge": String(repeating: "x", count: 2_000_001)]]]
        nodes["leaf"]!["message"] = message; r["mapping"] = nodes
        XCTAssertThrowsError(try ChatGPTRecordProjection.project(JSONSerialization.data(withJSONObject: r)))
        XCTAssertThrowsError(try ChatGPTRecordProjection.project(JSONSerialization.data(withJSONObject: record()), limits: .init(retainedNodes: 2)))
    }
    func testDuplicateSelectedFieldsAndEscapedMappingAliasesReject() throws {
        for text in [#"{"mapping":{"a":{},"\u0061":{}}}"#,
                     #"{"mapping":{"a":{"message":{"metadata":{"is_do_not_remember":true,"is_do_not_reme\u006dber":false}}}}}"#,
                     #"{"mapping":{"a":{"message":{"channel":null,"channel":"analysis"}}}}"#] {
            XCTAssertThrowsError(try ChatGPTRecordProjection.project(Data(text.utf8)))
        }
        XCTAssertNoThrow(try ChatGPTRecordProjection.project(Data(#"{"unknown":{"x":1,"x":2}}"#.utf8)))
    }
}

// Immutable pre-projection reference for differential behavior tests.
import Foundation
import CoreFoundation

/// Converts one bounded export record to ordinary app history, never executable
/// instructions. The caller must retain the complete original archive separately.
/// This does not extract ZIPs, write history, or resolve attachment ownership.
private enum LegacyChatGPTConversationRestore {
    enum Failure: Error { case invalidRecord, invalidTree, missingIdentity, invalidTimestamp, limit }
    struct UnresolvedContent: Sendable {
        let messageID: UUID
        let source: String
        let originalJSON: Data
    }
    struct Result: Sendable {
        var unresolvedContent: [UnresolvedContent] = []
        var conversation: Conversation?
        /// All mapping nodes not activated as visible messages, including sibling branches.
        var omittedMessages: Int
    }

    /// Non-UUID export IDs require a persisted, archive-scoped identity map supplied
    /// by the coordinator. Never mint random IDs here: retries must deduplicate.
    static func convert(_ data: Data, identities: [String: UUID]) throws -> Result {
        try Task.checkCancellation()
        guard data.count <= 16_000_000 else { throw Failure.limit }
        guard let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mapping = record["mapping"] as? [String: [String: Any]] else { throw Failure.invalidRecord }
        guard mapping.count <= 20_000 else { throw Failure.limit }
        if excluded(record) { return Result(conversation: nil, omittedMessages: mapping.count) }
        guard let externalID = record["id"] as? String, !externalID.isEmpty,
              let current = record["current_node"] as? String, !current.isEmpty else { throw Failure.invalidRecord }
        let id = try identity(externalID, key: "conversation:" + externalID, map: identities)
        let created = try timestamp(record["create_time"])
        let updated = try timestamp(record["update_time"])
        var branch: [[String: Any]] = [], visited = Set<String>(), cursor: String? = current
        while let key = cursor {
            try Task.checkCancellation()
            guard visited.insert(key).inserted, let node = mapping[key] else { throw Failure.invalidTree }
            branch.append(node)
            if node["parent"] is NSNull { cursor = nil }
            else if let parent = node["parent"] as? String, !parent.isEmpty { cursor = parent }
            else { throw Failure.invalidTree }
        }
        var messages: [ChatMessage] = [], messageIDs = Set<UUID>()
        var unresolved: [UnresolvedContent] = []
        for node in branch.reversed() {
            try Task.checkCancellation()
            guard let message = node["message"] as? [String: Any], !excluded(message),
                  let author = message["author"] as? [String: Any],
                  let roleName = author["role"] as? String,
                  let role = MessageRole(rawValue: roleName), role != .system else { continue }
            let metadata = message["metadata"] as? [String: Any]
            guard metadata?["is_visually_hidden_from_conversation"] as? Bool != true,
                  metadata?["is_user_system_message"] as? Bool != true else { continue }
            if role == .assistant {
                // JSON null is an unset optional routing field, not an internal channel.
                // Non-null unknown/malformed routing still fails closed.
                guard message["channel"] == nil || message["channel"] is NSNull || message["channel"] as? String == "final",
                      message["recipient"] == nil || message["recipient"] is NSNull || message["recipient"] as? String == "all" else { continue }
            }
            guard let content = message["content"] as? [String: Any],
                  let type = content["content_type"] as? String, ["text", "multimodal_text"].contains(type),
                  let parts = content["parts"] as? [Any] else { continue }
            guard parts.count <= 20_000 else { throw Failure.limit }
            let text = parts.compactMap { $0 as? String }.joined(separator: "\n")
            let hasUnresolved = parts.contains { !($0 is String) } || !(metadata?["attachments"] as? [Any] ?? []).isEmpty
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasUnresolved else { continue }
            guard text.utf8.count <= 1_000_000 else { throw Failure.limit }
            guard let externalMessage = message["id"] as? String, !externalMessage.isEmpty else { throw Failure.invalidRecord }
            let messageID = try identity(externalMessage, key: legacyMessageKey(conversationID: externalID, messageID: externalMessage), map: identities)
            guard messageIDs.insert(messageID).inserted else { throw Failure.invalidRecord }
            let attachments = metadata?["attachments"] as? [Any] ?? []
            guard attachments.count <= 2048 else { throw Failure.limit }
            let opaqueCount = parts.reduce(0) { $0 + ($1 is String ? 0 : 1) }
            guard unresolved.count + opaqueCount + attachments.count <= 2048 else { throw Failure.limit }
            for part in parts where !(part is String) {
                try Task.checkCancellation()
                unresolved.append(UnresolvedContent(messageID: messageID, source: "contentPart",
                    originalJSON: try JSONSerialization.data(withJSONObject: part, options: [.fragmentsAllowed, .sortedKeys])))
            }
            if !attachments.isEmpty {
                for attachment in attachments {
                    try Task.checkCancellation()
                    unresolved.append(UnresolvedContent(messageID: messageID, source: "attachmentMetadata",
                        originalJSON: try JSONSerialization.data(withJSONObject: attachment, options: [.fragmentsAllowed, .sortedKeys])))
                }
            }
            messages.append(ChatMessage(id: messageID, role: role, content: text,
                createdAt: try timestamp(message["create_time"]), state: restoredState(message)))
        }
        let conversation = Conversation(id: id, title: String((record["title"] as? String ?? "Imported conversation").prefix(200)),
            createdAt: created, updatedAt: updated, isArchived: record["is_archived"] as? Bool ?? false, messages: messages)
        return Result(unresolvedContent: unresolved, conversation: conversation, omittedMessages: mapping.count - messages.count)
    }
    private static func restoredState(_ message: [String: Any]) -> MessageState {
        let status = message["status"] as? String
        if status == "finished_successfully" { return .complete }
        if status == "failed" || status == "error" { return .failed }
        let author = message["author"] as? [String: Any]
        if status == nil && author?["role"] as? String == "user" { return .complete }
        return .interrupted
    }
    private static func excluded(_ record: [String: Any]) -> Bool {
        let metadata = record["metadata"] as? [String: Any]
        return record["is_do_not_remember"] as? Bool == true || metadata?["is_do_not_remember"] as? Bool == true
    }
    /// Versioned byte-length framing prevents ("a:b", "c") from aliasing ("a", "b:c").
    /// The coordinator must persist this exact key with its chosen UUID before commit.
    static func legacyMessageKey(conversationID: String, messageID: String) -> String {
        "message:v1:\(conversationID.utf8.count):\(conversationID):\(messageID.utf8.count):\(messageID)"
    }
    private static func identity(_ source: String, key: String, map: [String: UUID]) throws -> UUID {
        if let id = UUID(uuidString: source) { return id }
        guard let id = map[key] else { throw Failure.missingIdentity }
        return id
    }
    private static func timestamp(_ value: Any?) throws -> Date {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, (-62_135_596_800...253_402_300_799).contains(number.doubleValue) else { throw Failure.invalidTimestamp }
        return Date(timeIntervalSince1970: number.doubleValue)
    }
}
