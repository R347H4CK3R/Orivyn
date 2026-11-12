import XCTest
import Network
import NIOCore
import NIOHTTP1
import NIOEmbedded
@testable import JarvisEVO

final class WebSourceRepairTests: XCTestCase {
    func testThreeLongSourcesEachKeepMeaningfulEvidence() throws {
        let sources = (0..<3).map { source(String(repeating: String($0), count: 16_384)) }
        let context = try WebSourceContext(sources: sources)
        let entries = try decoded(context)
        XCTAssertLessThanOrEqual(context.json.utf8.count, 6_000)
        XCTAssertEqual(entries.count, 3)
        let counts = entries.map { ($0["text"] as! String).utf8.count }
        XCTAssertTrue(counts.allSatisfy { $0 >= 256 })
        XCTAssertLessThanOrEqual(counts.max()! - counts.min()!, 1)
        XCTAssertTrue(entries.allSatisfy { $0["contextTruncated"] as? Bool == true })
    }

    func testFairAllocationHandlesShortSourcesEscapesAndUnicode() throws {
        let texts = ["Short evidence", String(repeating: "\"\\\n", count: 2_000), String(repeating: "🦉", count: 4_096)]
        let context = try WebSourceContext(sources: texts.map { source($0) }, maximumBytes: 4_000)
        let entries = try decoded(context)
        XCTAssertLessThanOrEqual(context.json.utf8.count, 4_000)
        XCTAssertEqual(entries[0]["text"] as? String, "Short evidence")
        XCTAssertEqual(entries[0]["contextTruncated"] as? Bool, false)
        for index in 1...2 {
            let text = try XCTUnwrap(entries[index]["text"] as? String)
            XCTAssertGreaterThanOrEqual(text.utf8.count, 253)
            XCTAssertTrue(texts[index].hasPrefix(text))
            XCTAssertEqual(entries[index]["contextTruncated"] as? Bool, true)
        }
    }

    func testMetadataOnlyBudgetFailsRatherThanRetainingEmptyEvidence() throws {
        let longPath = "https://example.com/" + String(repeating: "a", count: 1_900)
        let sources = (0..<3).map { _ in source(String(repeating: "a", count: 1_000), url: longPath) }
        XCTAssertThrowsError(try WebSourceContext(sources: sources, maximumBytes: 12_500)) {
            XCTAssertEqual($0 as? WebSourceError, .contextTooSmall)
        }
        let context = try WebSourceContext(sources: sources, maximumBytes: 16_384)
        XCTAssertTrue(try decoded(context).allSatisfy { ($0["text"] as! String).utf8.count >= 256 })
    }

    func testInlineTagsPreserveNumericPunctuationAndWords() throws {
        for (html, expected) in [
            ("<p>The rate is 0.<b>5</b>%.</p>", "The rate is 0.5%."),
            ("<p>inter<em>oper</em>able</p>", "interoperable"),
            ("<p><a href='https://example.com'>A</a><span>B</span><i>C</i></p>", "ABC"),
            ("<div>First</div><p>Second<br>Third</p>", "First Second Third"),
            ("<p>A<span hidden>hidden</span>B<script>ignored()</script>C</p>", "A B C")
        ] { XCTAssertEqual(try WebTextExtractor.extract(Data(html.utf8), mediaType: "text/html").text, expected) }
    }

    func testUnicodeTitleTruncationTravelsThroughSourceAndCitation() throws {
        let value = try WebTextExtractor.extract(Data(("<title>" + String(repeating: "🦉", count: 61) + "</title><p>Body</p>").utf8), mediaType: "text/html")
        XCTAssertEqual(value.title, String(repeating: "🦉", count: 60))
        XCTAssertTrue(value.titleTruncated)
        XCTAssertFalse(value.truncated)
        let item = source("Body", title: value.title, titleTruncated: value.titleTruncated)
        let context = try WebSourceContext(sources: [item])
        XCTAssertEqual(try decoded(context)[0]["titleTruncated"] as? Bool, true)
        XCTAssertEqual(context.citation(for: item.id)?.titleTruncated, true)
    }

    func testAllTerminalErrorsAreNormalizedWithoutGuessingOffline() throws {
        for raw in [NWError.posix(.ENETDOWN), NWError.posix(.ENETUNREACH), NWError.posix(.ENOTCONN)] {
            let channel = EmbeddedChannel()
            let operation = WebReadOperation(promise: channel.eventLoop.makePromise(of: RetrievedWebBody.self))
            operation.finish(.failure(raw))
            XCTAssertThrowsError(try operation.promise.futureResult.wait()) { XCTAssertEqual($0 as? WebSourceError, .transportUnavailable) }
            _ = try? channel.finish()
        }
        let channel = EmbeddedChannel()
        let operation = WebReadOperation(promise: channel.eventLoop.makePromise(of: RetrievedWebBody.self))
        operation.finish(.failure(HTTPParserError.invalidContentLength))
        XCTAssertThrowsError(try operation.promise.futureResult.wait()) { XCTAssertEqual($0 as? WebSourceError, .invalidResponse) }
        _ = try? channel.finish()
    }

    private func source(_ text: String, url: String = "https://example.com/article", title: String? = nil, titleTruncated: Bool = false) -> WebSource {
        let url = URL(string: url)!
        return WebSource(id: UUID(), originalURL: url, finalURL: url, retrievedAt: Date(timeIntervalSince1970: 100),
                         mediaType: "text/plain", receivedBodyBytes: text.utf8.count, title: title,
                         titleTruncated: titleTruncated, text: text, textTruncated: false)
    }
    private func decoded(_ context: WebSourceContext) throws -> [[String: Any]] {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any])
        return try XCTUnwrap(object["sources"] as? [[String: Any]])
    }
}
