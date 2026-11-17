import XCTest
@testable import JarvisEVO

final class ChatResponsePolicyTests: XCTestCase {
    func testBuiltInPolicyStaysCompactWithoutTruncatingUserPreferences() {
        // Byte ceiling is a regression alarm, not a substitute for the native tokenizer gate.
        XCTAssertLessThanOrEqual(ChatResponsePolicy.instructions.utf8.count, 1900)
        for boundary in ["three", "Attachments", "external", "no-tools", "remote", "Automatic", "OCR"] {
            XCTAssertTrue(ChatResponsePolicy.instructions.contains(boundary))
        }
    }
    func testPolicyNamesOnlySupportedDirectReadsAndReviewedPlugins() {
        let prompt = ChatResponsePolicy.instructions
        for tool in ["list installed models", "show app information", "search saved memory"] {
            XCTAssertTrue(prompt.contains(tool))
        }
        XCTAssertTrue(prompt.contains("may propose one tool from its schemas locally, never execute it"))
        XCTAssertTrue(prompt.contains("With a connected catalog and concrete local model, fresh chat"))
        XCTAssertTrue(prompt.contains("Plugin calls require exact-call review"))
        XCTAssertTrue(prompt.contains("by the user in Orivyn's review screen"))
        XCTAssertTrue(prompt.contains("Jarvis cannot run a plugin call without the user reviewing its exact name and arguments"))
        XCTAssertTrue(prompt.contains("No policy-compliance exception"))
        XCTAssertTrue(prompt.contains("Provider authentication is not your approval to execute"))
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
    func testReasoningAfterVisiblePrefaceIsHiddenAtEverySplit() {
        let input = "Sure.\n<think>Private analysis</think>\nAnswer"
        for split in 0...input.count {
            let index = input.index(input.startIndex, offsetBy: split)
            var filter = ChatAnswerStream()
            var output = filter.append(String(input[..<index]))
            XCTAssertFalse(output.contains("Private"))
            output += filter.append(String(input[index...])) + filter.finish()
            XCTAssertEqual(output, "Sure.\n\nAnswer")
        }
    }
    func testMidAnswerReasoningAndUnclosedReasoningStayHidden() {
        var filter = ChatAnswerStream()
        var output = ""
        for char in "Answer<think>Private</think> continues<think>unfinished" {
            output += filter.append(String(char))
            XCTAssertFalse(output.contains("Private"))
            XCTAssertFalse(output.contains("unfinished"))
        }
        XCTAssertEqual(output + filter.finish(), "Answer continues")
    }
    func testCodeLiteralsSurviveAllChunkBoundaries() {
        let samples = [
            "Use `<think>example</think>` literally.",
            "Use ``<think>`example`</think>`` literally.",
            "Here:\n```python\nprint('<think>example</think>')\n```\nDone.",
            "Here:\n~~~html\n<think>example</think>\n~~~\nDone.",
            "Here:\n    <think>indented example</think>\nDone."
        ]
        for input in samples {
            var filter = ChatAnswerStream()
            var output = ""
            for char in input { output += filter.append(String(char)) }
            XCTAssertEqual(output + filter.finish(), input)
        }
    }
    func testReasoningFollowingClosedCodeIsHidden() {
        for input in ["`literal`<think>Private</think>Answer", "```\ncode\n```\n<think>Private</think>Answer", "~~~\ncode\n~~~\n<think>Private</think>Answer"] {
            var filter = ChatAnswerStream()
            var output = ""
            for char in input { output += filter.append(String(char)) }
            output += filter.finish()
            XCTAssertFalse(output.contains("Private"))
            XCTAssertTrue(output.hasSuffix("Answer"))
        }
    }
    func testEscapedAndUnmatchedBackticksCannotExposeReasoning() {
        let samples = ["Use `    <think>Private</think>Answer", "Use \\` literally.\n<think>Private</think>Answer",
                       "Use ` literally.\n<think>Private</think>Answer",
                       "Use `` literally.\n<think>Private</think>Answer"]
        for input in samples {
            for split in 0...input.count {
                let index = input.index(input.startIndex, offsetBy: split)
                var filter = ChatAnswerStream()
                var output = filter.append(String(input[..<index]))
                XCTAssertFalse(output.contains("Private"))
                output += filter.append(String(input[index...]))
                XCTAssertFalse(output.contains("Private"))
                output += filter.finish()
                XCTAssertFalse(output.contains("Private"))
                XCTAssertTrue(output.hasSuffix("Answer"))
            }
        }
    }
    func testNestedReasoningDoesNotExposeOuterTail() {
        var filter = ChatAnswerStream()
        var output = ""
        for char in "Visible<think>Private<think>Inner</think>Secret tail</think>Answer" {
            output += filter.append(String(char))
            XCTAssertFalse(output.contains("Private"))
            XCTAssertFalse(output.contains("Secret"))
        }
        XCTAssertEqual(output + filter.finish(), "VisibleAnswer")
    }
    func testLeadingIndentedCodeIsPreserved() {
        for input in ["    <think>example</think>", "\t<think>example</think>"] {
            var filter = ChatAnswerStream()
            var output = ""
            for char in input { output += filter.append(String(char)) }
            XCTAssertEqual(output + filter.finish(), input)
        }
    }
    func testClosedInlineCodeAtEOFIsPreserved() {
        var filter = ChatAnswerStream()
        let input = "Use `<think>literal</think>`"
        XCTAssertEqual(filter.append(input) + filter.finish(), input)
    }
    func testClosedCodeFenceWithWindowsLineEndingsDoesNotExposeReasoning() {
        let input = "```\r\ncode\r\n```\r\n<think>Private</think>Answer"
        var filter = ChatAnswerStream()
        var output = ""
        for char in input { output += filter.append(String(char)) }
        XCTAssertEqual(output + filter.finish(), "```\r\ncode\r\n```\r\nAnswer")
    }
    func testWhitespaceAfterReasoningDoesNotCreateFalseIndentedCodeMidline() {
        var filter = ChatAnswerStream()
        let input = "Visible<think>hidden</think>    <think>Private</think>Answer"
        XCTAssertEqual(filter.append(input) + filter.finish(), "VisibleAnswer")
    }
    func testTildesInsideMultilineInlineCodeDoNotChangeFenceState() {
        let input = "Use `<think>literal</think>\n~~~\nstill literal` then <think>Private</think>Answer"
        var filter = ChatAnswerStream()
        var output = ""
        for char in input { output += filter.append(String(char)) }
        XCTAssertEqual(output + filter.finish(), "Use `<think>literal</think>\n~~~\nstill literal` then Answer")
    }
    func testUnclosedReasoningIsNotAnAnswer() {
        var filter = ChatAnswerStream()
        XCTAssertEqual(filter.append("<think>unfinished"), "")
        XCTAssertEqual(filter.finish(), "")
    }
    func testFinalizationNeverFlushesUnclosedReasoningOrPartialClosingTags() {
        for suffix in ["unfinished", "unfinished</thi", "unfinished</think", "unfinished</think >"] {
            var filter = ChatAnswerStream()
            XCTAssertEqual(filter.append("Visible<think>" + suffix), "Visible")
            XCTAssertEqual(filter.finish(), "")
            XCTAssertEqual(filter.finish(), "")
        }
    }
    func testPartialOpeningOutsideCodeNeverEmitsReasoningBeforeRecognition() {
        var filter = ChatAnswerStream()
        XCTAssertEqual(filter.append("Visible<thi"), "Visible")
        XCTAssertEqual(filter.append("nk>Private</thi"), "")
        XCTAssertEqual(filter.append("nk>Answer"), "Answer")
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
