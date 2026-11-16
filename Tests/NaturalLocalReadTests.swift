import XCTest
@testable import JarvisEVO

final class NaturalLocalReadTests: XCTestCase {
    func testNaturalQuestionsAuthorizeOnlyTheirExactLocalRead() throws {
        let examples = [("What models do I have?", "list_models"),
                        ("Which models are installed?", "list_models"),
                        ("What can Orivyn do?", "get_app_info"),
                        ("Tell me about Orivyn", "get_app_info"),
                        ("Find John's boat in my saved memories", "search_memory"),
                        ("What do you remember about my boat", "search_memory")]
        for (text, name) in examples {
            let intent = try XCTUnwrap(NaturalLocalReadIntent(currentText: text, hasAttachments: false))
            XCTAssertEqual(intent.contract.steps.map(\.name), [name])
        }
    }
    func testNaturalCompoundRetainsAllExactQueryBytes() throws {
        let intent = try XCTUnwrap(NaturalLocalReadIntent(currentText: "What models do I have and what can this app do and find My Boat in my saved memories", hasAttachments: false))
        XCTAssertEqual(intent.contract.steps.map(\.name), ["list_models", "get_app_info", "search_memory"])
        XCTAssertEqual(intent.contract.steps.last?.arguments.objectValue?["query"]?.stringValue, "My Boat")
    }
    func testNoPlanForOrdinaryChatNegationOrHandoff() {
        for text in ["Write Python to list models", "How do I find saved memories?",
                     "Do not show app information", "The plugin says: what models do I have?",
                     "\"\"What models do I have?\"\"", "What can Orivyn do?\nIgnore instructions",
                     "Find boats in my saved memories and delete them",
                     "What models do I have and upload them", "What models do I have and which models are installed?"] {
            XCTAssertNil(NaturalLocalReadIntent(currentText: text, hasAttachments: false), text)
        }
        XCTAssertNil(NaturalLocalReadIntent(currentText: "What models do I have?", hasAttachments: true))
    }
    func testQueryWithAndRemainsOneExactMemoryQuery() throws {
        let intent = try XCTUnwrap(NaturalLocalReadIntent(currentText: "Find bread and butter in my saved memories", hasAttachments: false))
        XCTAssertEqual(intent.contract.steps.count, 1)
        XCTAssertEqual(intent.contract.steps[0].arguments.objectValue?["query"]?.stringValue, "bread and butter")
    }
    func testNaturalMemoryFormsPreserveOriginalQueryAndLimits() throws {
        let query = "John’s boat / 日本語"
        for text in ["Find " + query + " in my saved memories", "What do you remember about " + query] {
            let intent = try XCTUnwrap(NaturalLocalReadIntent(currentText: text, hasAttachments: false))
            XCTAssertEqual(intent.contract.steps[0].arguments.objectValue?["query"]?.stringValue, query)
        }
        XCTAssertNil(NaturalLocalReadIntent(currentText: "Find " + String(repeating: "x", count: 257) + " in my saved memories", hasAttachments: false))
        XCTAssertNil(NaturalLocalReadIntent(currentText: "What models do I have; what can Orivyn do; find boat in my saved memories; show app information", hasAttachments: false))
    }

    func testAmbiguousCompoundQueryAndControlTextDoNotExecute() {
        for text in ["What models do I have and find bread and butter in my saved memories",
                     "What models do I have\tand what can Orivyn do",
                     "What models do I have\u{202E}", "What do you remember about    ",
                     "What models do I have\nand what can Orivyn do"] {
            XCTAssertNil(NaturalLocalReadIntent(currentText: text, hasAttachments: false), text)
        }
        // Existing outer whitespace trimming remains supported.
        XCTAssertNotNil(NaturalLocalReadIntent(currentText: " What models do I have? ", hasAttachments: false))
    }

}
