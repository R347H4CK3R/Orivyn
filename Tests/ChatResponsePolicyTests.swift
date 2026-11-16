import XCTest
@testable import JarvisEVO

final class ChatResponsePolicyTests: XCTestCase {
    func testPolicyNamesOnlySupportedDirectReadsAndReviewedPlugins() {
        let prompt = ChatResponsePolicy.instructions
        for tool in ["list installed models", "show app information", "search saved memory"] {
            XCTAssertTrue(prompt.contains(tool))
        }
        XCTAssertTrue(prompt.contains("Plugin calls require exact-call review"))
        XCTAssertFalse(prompt.contains("Chat does not automatically call device tools"))
    }
    func testCapabilityInventoryIsExplicitAndDoesNotClaimDeviceOrFileAccess() {
        let prompt = ChatResponsePolicy.instructions
        XCTAssertTrue(prompt.contains("DIRECT LOCAL READS (complete list)"))
        for name in ["list_models", "get_app_info", "search_memory"] {
            XCTAssertTrue(prompt.contains(name))
        }
        XCTAssertTrue(prompt.contains("Not general filesystem access or device/user information"))
    }
    func testEveryAdvertisedReadMatchesAnActualTypedRequest() throws {
        let requests = ["list installed models", "show app information", "search saved memory for cedar"]
        let names = try requests.map { request in
            let parsed = try XCTUnwrap(ChatLocalTaskRequest(draft: request, hasAttachments: false))
            return try XCTUnwrap(parsed.proposedChecklist?.steps.first?.name)
        }
        XCTAssertEqual(Set(names), Set(DirectChatRead.allCases.map(\.rawValue)))
        XCTAssertEqual(names.count, 3)
    }
    func testWritingCodeIsNotExecutionAndRepliesDoNotEcho() {
        let prompt = ChatResponsePolicy.instructions
        XCTAssertTrue(prompt.contains("write Python"))
        XCTAssertTrue(prompt.contains("Writing code as text is different from executing it"))
        XCTAssertTrue(prompt.contains("Do not repeat or paraphrase the user's request as an opening"))
        XCTAssertTrue(prompt.contains("Do not invent tools"))
    }
    func testReasoningNeverAppearsDuringCharacterByCharacterStreaming() {
        var filter = ChatAnswerStream()
        var result = ""
        for char in " \n<think>Private analysis 🧠</think>\nprint('Hello')" {
            result += filter.append(String(char))
            XCTAssertFalse(result.contains("Private"))
            XCTAssertFalse(result.contains("<think>"))
        }
        result += filter.finish()
        XCTAssertEqual(result, "\nprint('Hello')")
    }
    func testEverySplitBoundaryAndMultipleLeadingBlocks() {
        let text = "<think>analysis</think>\n<think>more</think>\nAnswer"
        for split in 0...text.count {
            let index = text.index(text.startIndex, offsetBy: split)
            var filter = ChatAnswerStream()
            let output = filter.append(String(text[..<index])) + filter.append(String(text[index...])) + filter.finish()
            XCTAssertEqual(output, "\nAnswer")
        }
    }
    func testUnclosedReasoningIsNotAnAnswer() {
        var filter = ChatAnswerStream()
        XCTAssertEqual(filter.append("<think>unfinished"), "")
        XCTAssertEqual(filter.finish(), "")
    }
    func testLiteralTagsInAnswerCodeArePreserved() {
        var filter = ChatAnswerStream()
        let answer = "```python\nprint('<think>example</think>')\n```"
        XCTAssertEqual(filter.append(answer) + filter.finish(), answer)
    }
    func testAnswerIndentationAfterReasoningIsPreserved() {
        var filter = ChatAnswerStream()
        XCTAssertEqual(filter.append("<think>x</think>\n    print('Hello')") + filter.finish(), "\n    print('Hello')")
    }
    func testLeadingCodeWhitespaceAndLiteralTagPrefixesSurvive() {
        for answer in ["    print('Hello')", "\n\nAnswer", "<", "<t", "<thi"] {
            var filter = ChatAnswerStream()
            XCTAssertEqual(filter.append(answer) + filter.finish(), answer)
        }
    }
    func testOrdinaryMarkupAndUnicodeArePreserved() {
        for answer in ["<table>hello</table>", "Sure: 🧠", "print('Hello')"] {
            var filter = ChatAnswerStream()
            XCTAssertEqual(filter.append(answer) + filter.finish(), answer)
        }
    }
}
