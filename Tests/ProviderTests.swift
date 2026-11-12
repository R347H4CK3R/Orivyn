import XCTest
@testable import JarvisEVO

final class ProviderTests: XCTestCase {
    func testSSEParsesChunksAndDone() throws {
        var decoder = SSEDecoder()
        XCTAssertEqual(try decoder.consume(line: "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"), .token("Hello"))
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
