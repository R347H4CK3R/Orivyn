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
        let bytes = Array("data: {\"choices\":[{\"delta\":{\"content\":\"€\"}}]}\r\n\r\n".utf8)
        var events: [SSEEvent] = []
        for byte in bytes { if let event = try decoder.consume(byte: byte) { events.append(event) } }
        XCTAssertEqual(events, [.token("€")])
    }
    func testSSEByteDecoderRejectsOversizedLineBeforeNewline() throws {
        var decoder = SSEByteDecoder(maximumLineBytes: 16)
        for _ in 0..<16 { XCTAssertNil(try decoder.consume(byte: 65)) }
        XCTAssertThrowsError(try decoder.consume(byte: 65))
    }
    func testSSEByteDecoderSupportsAllStandardLineEndings() throws {
        for ending in ["\n", "\r\n", "\r"] {
            var decoder = SSEByteDecoder()
            let lines = [#"data: {"choices":[{"delta":{"content":"café 🦉"}}]}"#,
                         #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#, "data: [DONE]"]
            var events: [SSEEvent] = []
            for byte in (lines.joined(separator: ending + ending) + ending + ending).utf8 {
                if let event = try decoder.consume(byte: byte) { events.append(event) }
            }
            XCTAssertEqual(events, [.token("café 🦉"), .ignored, .done], ending.debugDescription)
        }
    }

    func testSSEByteDecoderLineLimitDoesNotCountCRLFDelimiters() throws {
        let line = ":0123456789abcdef"
        for ending in ["\n", "\r\n", "\r"] {
            var decoder = SSEByteDecoder(maximumLineBytes: line.utf8.count)
            var events: [SSEEvent] = []
            XCTAssertNoThrow(try (line + ending).utf8.forEach { byte in
                if let event = try decoder.consume(byte: byte) { events.append(event) }
            })
            XCTAssertEqual(events, [])
        }
    }

    func testSSEMultilineJSONDispatchesOnlyAtBlankLine() throws {
        var decoder = SSEByteDecoder()
        let source = "data: {\"choices\": [\n" + "data: {\"delta\":{\"content\":\"joined\"}}]}\n"
        for byte in source.utf8 { XCTAssertNil(try decoder.consume(byte: byte)) }
        XCTAssertEqual(try decoder.consume(byte: 10), .token("joined"))
    }

    func testSSEInitialUTF8BOMDoesNotDiscardFirstToken() throws {
        var decoder = SSEByteDecoder()
        let source = "\u{feff}" + #"data: {"choices":[{"delta":{"content":"first"}}]}"# + "\n\n"
        var events: [SSEEvent] = []
        for byte in source.utf8 { if let event = try decoder.consume(byte: byte), event != .ignored { events.append(event) } }
        XCTAssertEqual(events, [.token("first")])
    }

    func testSSEDoneIsNotAcceptedUntilItsEventTerminator() throws {
        var decoder = SSEByteDecoder()
        let stop = #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"# + "\n\n"
        for byte in stop.utf8 { _ = try decoder.consume(byte: byte) }
        for byte in "data: [DONE]\n".utf8 { XCTAssertNil(try decoder.consume(byte: byte)) }
        XCTAssertEqual(try decoder.consume(byte: 10), .done)
    }

    func testSSEEventBudgetIncludesInsertedNewlinesAcrossShortLines() throws {
        var decoder = SSEByteDecoder(maximumLineBytes: 32, maximumEventBytes: 12)
        for byte in "data:123456\n".utf8 { XCTAssertNil(try decoder.consume(byte: byte)) }
        for byte in "data:123456".utf8 { XCTAssertNil(try decoder.consume(byte: byte)) }
        XCTAssertThrowsError(try decoder.consume(byte: 10))
    }

    func testSSECommentsAndMetadataBetweenDataLinesDoNotAlterPayload() throws {
        var decoder = SSEByteDecoder()
        let source = "data:{\"choices\":[\r\n: keep alive\r\nid: 17\r\nretry: 500\r\nevent: message\r\n" +
            #"data:{"delta":{"content":"literal + café"}}]}"# + "\r\n\r\n"
        var events: [SSEEvent] = []
        for byte in source.utf8 { if let event = try decoder.consume(byte: byte) { events.append(event) } }
        XCTAssertEqual(events, [.token("literal + café")])
    }

    func testSSEInvalidUTF8IsRejectedBeforeDispatch() throws {
        var decoder = SSEByteDecoder()
        for byte in [UInt8(100), 97, 116, 97, 58, 0xff] { XCTAssertNil(try decoder.consume(byte: byte)) }
        XCTAssertThrowsError(try decoder.consume(byte: 10))
    }

    func testMissingOrEmptyRemoteModelIsRejected() {
        XCTAssertThrowsError(try RemoteEndpoint(baseURL: "https://example.com/v1", model: "  "))
    }
}
