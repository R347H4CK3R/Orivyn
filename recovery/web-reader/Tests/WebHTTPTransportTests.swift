import XCTest
import NIOCore
import NIOHTTP1
import NIOEmbedded
@testable import JarvisEVO

final class WebHTTPTransportTests: XCTestCase {
    // These exercise production wire limits and the pinned NIO framing decoder without networking.
    func testChunkedAndLengthFramingProduceOnlyActualBody() throws {
        for wire in ["HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello",
                     "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhe\r\n3\r\nllo\r\n0\r\n\r\n"] {
            let harness = try Harness()
            for byte in wire.utf8 { try harness.feed(Data([byte])) }
            XCTAssertEqual(try harness.result().data, Data("hello".utf8))
        }
    }

    func testRedirectAuthAndCompressionNeverProduceSource() throws {
        for (wire, expected) in [
            ("HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1/\r\nContent-Length: 0\r\n\r\n", WebSourceError.redirectBlocked),
            ("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=x\r\nContent-Length: 0\r\n\r\n", .authenticationRequired),
            ("HTTP/1.1 429 Too Many Requests\r\nRetry-After: 0\r\nContent-Length: 0\r\n\r\n", .rateLimited),
            ("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Encoding: gzip\r\nContent-Length: 0\r\n\r\n", .encodedResponse)
        ] {
            let harness = try Harness()
            try harness.feed(Data(wire.utf8))
            XCTAssertThrowsError(try harness.result()) { XCTAssertEqual($0 as? WebSourceError, expected) }
            XCTAssertFalse(harness.channel.isActive)
        }
    }

    func testInvalidDuplicateLengthAndTruncatedFramesFail() throws {
        for wire in ["HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nx",
                     "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\n\r\nZ\r\nx\r\n0\r\n\r\n",
                     "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nx"] {
            let harness = try Harness()
            try? harness.feed(Data(wire.utf8))
            try? harness.channel.close().wait()
            XCTAssertThrowsError(try harness.result())
        }
    }

    func testHeaderAndBodyLimitsBoundProductionPipeline() throws {
        let header = try Harness()
        try header.feed(Data(("HTTP/1.1 200 OK\r\nX: " + String(repeating: "a", count: 16_384)).utf8))
        XCTAssertThrowsError(try header.result())
        let body = try Harness()
        try body.feed(Data("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n".utf8))
        try body.feed(Data(repeating: 65, count: 262_145))
        XCTAssertThrowsError(try body.result()) { XCTAssertEqual($0 as? WebSourceError, .bodyTooLarge) }
    }

    func testRequestContainsNoCredentialsOrConversationAndUsesOriginalHost() throws {
        let harness = try Harness()
        var outbound = ""
        while let buffer = try harness.channel.readOutbound(as: ByteBuffer.self) {
            outbound += buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) ?? ""
        }
        XCTAssertTrue(outbound.hasPrefix("GET /article HTTP/1.1\r\n"))
        XCTAssertTrue(outbound.lowercased().contains("host: example.com\r\n"))
        XCTAssertTrue(outbound.lowercased().contains("accept-encoding: identity\r\n"))
        XCTAssertFalse(outbound.lowercased().contains("cookie:"))
        XCTAssertFalse(outbound.lowercased().contains("authorization:"))
        XCTAssertFalse(outbound.lowercased().contains("referer:"))
        harness.operation.finish(.failure(CancellationError()))
        XCTAssertThrowsError(try harness.result()) { XCTAssertTrue($0 is CancellationError) }
    }

    func testCancellationWinsExactlyOnceAndClosesConnection() throws {
        let harness = try Harness()
        harness.operation.finish(.failure(CancellationError()))
        harness.operation.finish(.failure(WebSourceError.timeout))
        XCTAssertThrowsError(try harness.result()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(harness.channel.isActive)
    }
}

private final class Harness {
    let channel = EmbeddedChannel()
    let operation: WebReadOperation
    init() throws {
        operation = WebReadOperation(promise: channel.eventLoop.makePromise(of: RetrievedWebBody.self))
        operation.install(channel)
        try channel.pipeline.syncOperations.addHandler(WebWireLimitHandler())
        try channel.pipeline.syncOperations.addHandler(HTTPRequestEncoder())
        try channel.pipeline.syncOperations.addHandler(ByteToMessageHandler(HTTPResponseDecoder(
            leftOverBytesStrategy: .dropBytes, informationalResponseStrategy: .forward)))
        try channel.pipeline.syncOperations.addHandler(NIOHTTPRequestHeadersValidator())
        try channel.pipeline.syncOperations.addHandler(WebHTTPResponseHandler(
            request: UserSuppliedWebURL("https://example.com/article"), operation: operation, progress: { _ in }))
        try channel.connect(to: SocketAddress(ipAddress: "1.1.1.1", port: 443)).wait()
    }
    func feed(_ bytes: Data) throws {
        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        _ = try channel.writeInbound(buffer)
    }
    func result() throws -> RetrievedWebBody { try operation.promise.futureResult.wait() }
    deinit { _ = try? channel.finish() }
}
