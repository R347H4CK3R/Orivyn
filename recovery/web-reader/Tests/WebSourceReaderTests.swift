import XCTest
@testable import JarvisEVO

final class WebSourceReaderTests: XCTestCase {
    func testOfflineReturnsExplicitFailureWithoutTransport() async throws {
        let reader = WebSourceReader(transport: NeverTransport())
        do { _ = try await reader.read(try UserSuppliedWebURL("https://1.1.1.1/"), isOnline: false); XCTFail() }
        catch { XCTAssertEqual(error as? WebSourceError, .offline) }
    }

    func testProvenanceAndTextReflectActualResponse() async throws {
        let date = Date(timeIntervalSince1970: 100)
        let reader = WebSourceReader(transport: FixtureTransport(), minimumInterval: .zero, now: { date })
        let source = try await reader.read(try UserSuppliedWebURL("https://1.1.1.1/article"), isOnline: true)
        XCTAssertEqual(source.originalURL.absoluteString, "https://1.1.1.1/article")
        XCTAssertEqual(source.finalURL, source.originalURL)
        XCTAssertEqual(source.retrievedAt, date)
        XCTAssertEqual(source.title, "Fixture")
        XCTAssertEqual(source.text, "Actual content")
        XCTAssertFalse(source.textTruncated)
        XCTAssertEqual(source.receivedBodyBytes, 43)
    }

    func testBatchKeepsSuccessfulSourcesAndIndividualFailures() async throws {
        let reader = WebSourceReader(transport: FixtureTransport(), minimumInterval: .zero)
        let request = [try UserSuppliedWebURL("https://1.1.1.1/article"), try UserSuppliedWebURL("https://8.8.8.8/fail")]
        let result = try await reader.readMany(request, isOnline: true)
        XCTAssertEqual(result.count, 2)
        XCTAssertNotNil(result[0].source)
        XCTAssertEqual(result[1].error, .httpStatus(503))
        XCTAssertThrowsError(try WebSourceContext(sources: [], maximumBytes: 800))
    }

    func testContextIsBoundedJSONAndCitationsOnlyResolveRetrievedSourceIDs() async throws {
        let reader = WebSourceReader(transport: FixtureTransport(), minimumInterval: .zero)
        let source = try await reader.read(try UserSuppliedWebURL("https://1.1.1.1/article"), isOnline: true)
        let context = try WebSourceContext(sources: [source], maximumBytes: 2000)
        XCTAssertLessThanOrEqual(context.json.utf8.count, 2000)
        let decoded = try JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any]
        XCTAssertEqual(decoded?["trust"] as? String, "untrusted_web_content")
        XCTAssertEqual(context.citation(for: source.id)?.url, source.finalURL)
        XCTAssertNil(context.citation(for: UUID()))
        XCTAssertThrowsError(try WebSourceContext(sources: [source], maximumBytes: 20))
    }

    func testCancellationBeforeReadNeverRunsTransport() async throws {
        let reader = WebSourceReader(transport: NeverTransport())
        let task = Task { () throws -> WebSource in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.read(UserSuppliedWebURL("https://1.1.1.1/"), isOnline: true)
        }
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
}

private struct NeverTransport: WebSourceTransport {
    func retrieve(_ request: UserSuppliedWebURL, progress: @escaping @Sendable (Int) -> Void) async throws -> RetrievedWebBody {
        XCTFail("Network must not be reached")
        throw WebSourceError.invalidResponse
    }
}

private struct FixtureTransport: WebSourceTransport {
    func retrieve(_ request: UserSuppliedWebURL, progress: @escaping @Sendable (Int) -> Void) async throws -> RetrievedWebBody {
        if request.url.host == "8.8.8.8" { throw WebSourceError.httpStatus(503) }
        let data = Data("<title>Fixture</title><p>Actual content</p>".utf8)
        progress(data.count)
        return RetrievedWebBody(url: request.url, mediaType: "text/html", data: data)
    }
}
