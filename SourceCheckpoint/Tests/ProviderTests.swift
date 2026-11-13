import XCTest
@testable import JarvisEVO

final class ProviderTests: XCTestCase {
    func testSSEParsesChunksAndDone() throws {
        var decoder = SSEDecoder()
        XCTAssertEqual(try decoder.consume(line: "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"), .token("Hello"))
        XCTAssertEqual(try decoder.consume(line: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#), .ignored)
        XCTAssertEqual(try decoder.consume(line: "data: [DONE]"), .done)
    }
    func testSSECommentsAndMetadataDoNotBecomeTokens() throws {
        var decoder = SSEDecoder()
        XCTAssertEqual(try decoder.consume(line: ": keep-alive"), .ignored)
        XCTAssertEqual(try decoder.consume(line: "event: message"), .ignored)
        XCTAssertEqual(try decoder.consume(line: "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}"), .ignored)
    }
    func testMalformedSSEAndProviderErrorAreNotSuccess() {
        var decoder = SSEDecoder()
        XCTAssertThrowsError(try decoder.consume(line: "data: invalid"))
        XCTAssertThrowsError(try decoder.consume(line: "data: {\"error\":{\"message\":\"Quota reached\"}}"))
    }
    func testIncompleteOrUnsupportedProviderFinishDoesNotBecomeSuccess() throws {
        for reason in ["length", "content_filter", "tool_calls", "function_call", "unknown_reason"] {
            var decoder = SSEDecoder()
            XCTAssertEqual(try decoder.consume(line: #"data: {"choices":[{"delta":{"content":"Partial"}}]}"#), .token("Partial"))
            let envelope: [String: Any] = ["choices": [["delta": [String: String](), "finish_reason": reason] as [String: Any]]]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
            XCTAssertThrowsError(try decoder.consume(line: "data: " + json))
        }
    }

    func testDoneWithoutSupportedStopIsNotCompletion() throws {
        var decoder = SSEDecoder()
        XCTAssertEqual(try decoder.consume(line: #"data: {"choices":[{"delta":{"content":"Partial"}}]}"#), .token("Partial"))
        XCTAssertThrowsError(try decoder.consume(line: "data: [DONE]"))
    }

    func testUnsupportedToolDeltaIsRejectedBeforeContentCanBeSpoken() {
        for delta in [#"{"content":"Attempt","tool_calls":[{}]}"#, #"{"function_call":{}}"#] {
            var decoder = SSEDecoder()
            XCTAssertThrowsError(try decoder.consume(line: "data: {\"choices\":[{\"delta\":" + delta + "}]}"))
        }
    }

    func testContentAfterStopAndDataAfterDoneAreRejected() throws {
        var decoder = SSEDecoder()
        XCTAssertEqual(try decoder.consume(line: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#), .ignored)
        XCTAssertThrowsError(try decoder.consume(line: #"data: {"choices":[{"delta":{"content":"Late"}}]}"#))
        var finished = SSEDecoder()
        _ = try finished.consume(line: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
        XCTAssertEqual(try finished.consume(line: "data: [DONE]"), .done)
        XCTAssertThrowsError(try finished.consume(line: "data: [DONE]"))
    }

    func testUsageAfterStopIsAllowedButDuplicateStopAndRefusalAreRejected() throws {
        var decoder = SSEDecoder()
        let stop = #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        _ = try decoder.consume(line: stop)
        XCTAssertEqual(try decoder.consume(line: #"data: {"choices":[],"usage":{"completion_tokens":2}}"#), .ignored)
        XCTAssertThrowsError(try decoder.consume(line: stop))
        var refusal = SSEDecoder()
        XCTAssertThrowsError(try refusal.consume(line: #"data: {"choices":[{"delta":{"content":"Prior","refusal":"Provider policy"}}]}"#))
    }

    func testNormalStopAllowsFinalContentAndDone() throws {
        var decoder = SSEDecoder()
        XCTAssertEqual(try decoder.consume(line: #"data: {"choices":[{"delta":{"content":"Final"},"finish_reason":"stop"}]}"#), .token("Final"))
        XCTAssertEqual(try decoder.consume(line: "data: [DONE]"), .done)
    }

    func testRemoteEndpointRequiresHTTPSAndRejectsEmbeddedCredentials() {
        XCTAssertThrowsError(try RemoteEndpoint(baseURL: "http://example.com/v1", model: "test"))
        XCTAssertThrowsError(try RemoteEndpoint(baseURL: "https://user:secret@example.com/v1", model: "test"))
        XCTAssertThrowsError(try RemoteEndpoint(baseURL: "https://example.com/v1?token=secret", model: "test"))
        XCTAssertNoThrow(try RemoteEndpoint(baseURL: "https://example.com/v1", model: "test"))
    }
    func testSSEByteDecoderHandlesFragmentedUTF8() throws {
        var decoder = SSEByteDecoder()
        let bytes = Array("data: {\"choices\":[{\"delta\":{\"content\":\"€\"}}]}\r\n".utf8)
        var events: [SSEEvent] = []
        for byte in bytes { if let event = try decoder.consume(byte: byte) { events.append(event) } }
        XCTAssertEqual(events, [.token("€")])
    }
    func testSSEByteDecoderRejectsOversizedLineBeforeNewline() throws {
        var decoder = SSEByteDecoder(maximumLineBytes: 16)
        for _ in 0..<16 { XCTAssertNil(try decoder.consume(byte: 65)) }
        XCTAssertThrowsError(try decoder.consume(byte: 65))
    }
    func testMissingOrEmptyRemoteModelIsRejected() {
        XCTAssertThrowsError(try RemoteEndpoint(baseURL: "https://example.com/v1", model: "  "))
    }
}
