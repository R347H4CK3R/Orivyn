import Foundation
import Network
import Security
import NIOCore
import NIOHTTP1
import NIOTransportServices

/// Native-unverified draft. No URLSession fallback: the selected public literal is the socket destination.
struct PinnedWebTransport: WebSourceTransport {
    private let resolver: any WebDNSResolving
    init(resolver: any WebDNSResolving = PublicWebDNSResolver()) { self.resolver = resolver }

    func retrieve(_ request: UserSuppliedWebURL, progress: @escaping @Sendable (Int) -> Void) async throws -> RetrievedWebBody {
        try Task.checkCancellation()
        let address = try await resolver.resolve(request)
        try Task.checkCancellation()
        let group = NIOTSEventLoopGroup(loopCount: 1)
        let loop = group.next()
        let operation = WebReadOperation(promise: loop.makePromise(of: RetrievedWebBody.self))
        let deadline = loop.scheduleTask(in: .seconds(30)) { operation.finish(.failure(WebSourceError.timeout)) }
        let outcome: Result<RetrievedWebBody, Error>
        do {
            let body = try await withTaskCancellationHandler {
                let tls = Self.tlsOptions(hostname: request.hostname)
                let bootstrap = NIOTSConnectionBootstrap(group: group)
                    .connectTimeout(.seconds(10))
                    .channelOption(NIOTSChannelOptions.waitForActivity, value: false)
                    .channelOption(NIOTSChannelOptions.enablePeerToPeer, value: false)
                    .channelOption(NIOTSChannelOptions.maximumReceiveLength, value: 8_192)
                    .tlsOptions(tls)
                    .channelInitializer { channel in
                        operation.install(channel)
                        return channel.eventLoop.makeCompletedFuture {
                            try channel.pipeline.syncOperations.addHandler(WebWireLimitHandler())
                            // Official NIO framing parser; no decompression handler, upgrades, or redirect layer.
                            try channel.pipeline.syncOperations.addHandler(HTTPRequestEncoder())
                            try channel.pipeline.syncOperations.addHandler(ByteToMessageHandler(
                                HTTPResponseDecoder(leftOverBytesStrategy: .dropBytes, informationalResponseStrategy: .forward)))
                            try channel.pipeline.syncOperations.addHandler(NIOHTTPRequestHeadersValidator())
                            try channel.pipeline.syncOperations.addHandler(WebHTTPResponseHandler(request: request, operation: operation, progress: progress))
                        }
                    }
                // SocketAddress(ipAddress:) parses a literal. It does not perform DNS resolution.
                let socket = try SocketAddress(ipAddress: address.literal, port: 443)
                bootstrap.connect(to: socket).whenFailure { operation.finish(.failure($0)) }
                return try await operation.promise.futureResult.get()
            } onCancel: { operation.finish(.failure(CancellationError())) }
            outcome = .success(body)
        } catch { outcome = .failure(error) }
        deadline.cancel()
        // Every terminal outcome closes the only channel. No pool or TLS session reuse is retained.
        try? await group.shutdownGracefully()
        try Task.checkCancellation()
        return try outcome.get()
    }

    private static func tlsOptions(hostname: String) -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        sec_protocol_options_add_tls_application_protocol(options.securityProtocolOptions, "http/1.1")
        // Apple documents this as the name used to verify the certificate, not merely an SNI hint.
        sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, hostname)
        sec_protocol_options_set_peer_authentication_required(options.securityProtocolOptions, true)
        sec_protocol_options_set_tls_resumption_enabled(options.securityProtocolOptions, false)
        sec_protocol_options_set_tls_tickets_enabled(options.securityProtocolOptions, false)
        sec_protocol_options_set_tls_renegotiation_enabled(options.securityProtocolOptions, false)
        // Certificate AIA/OCSP URLs are also untrusted destinations. Disable network fetching for this trust evaluation,
        // using the platform trust store and the original hostname, with no anchor or error override.
        // This is not a claim that Security.framework performs no independent OS maintenance traffic.
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, trust, complete in
            let systemTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            complete(WebTLSIdentity.evaluate(systemTrust, hostname: hostname))
        }, DispatchQueue(label: "app.jarvisevo.source-tls-verify"))
        return options
    }


}

/// Cross-thread cancellation and exactly-once completion. All mutable fields are lock protected.
final class WebReadOperation: @unchecked Sendable {
    let promise: EventLoopPromise<RetrievedWebBody>
    private let lock = NSLock()
    private var channel: (any Channel)?
    private var completed = false
    init(promise: EventLoopPromise<RetrievedWebBody>) { self.promise = promise }

    var isFinished: Bool { lock.withLock { completed } }
    func install(_ channel: any Channel) {
        let close = lock.withLock { () -> Bool in
            guard !completed else { return true }
            self.channel = channel
            return false
        }
        if close { channel.close(promise: nil) }
    }
    func finish(_ result: Result<RetrievedWebBody, Error>) {
        let state = lock.withLock { () -> (Bool, (any Channel)?) in
            guard !completed else { return (false, nil) }
            completed = true
            let channel = channel
            self.channel = nil
            return (true, channel)
        }
        guard state.0 else { return }
        state.1?.close(promise: nil)
        promise.completeWith(result.mapError(WebTransportErrorPolicy.normalize))
    }
}

/// Bounds plaintext wire bytes before NIO's framing parser, including header/chunk/trailer overhead.
/// OS TLS buffers/records are outside this bound. This does not parse HTTP framing.
final class WebWireLimitHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    private var received = 0
    private var headerBytes = 0
    private var delimiter: UInt32 = 0
    private var headerFinished = false

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        guard buffer.readableBytes <= 294_912 - received else { fail(context); return }
        received += buffer.readableBytes
        if !headerFinished {
            for byte in buffer.readableBytesView {
                headerBytes += 1
                guard headerBytes <= 16_384 else { fail(context); return }
                delimiter = (delimiter << 8) | UInt32(byte)
                if delimiter == 0x0D0A0D0A { headerFinished = true; break }
            }
        }
        context.fireChannelRead(data)
    }
    private func fail(_ context: ChannelHandlerContext) {
        context.fireErrorCaught(WebSourceError.responseLimitExceeded)
        context.close(promise: nil)
    }
}

final class WebHTTPResponseHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart
    private let request: UserSuppliedWebURL
    private let operation: WebReadOperation
    private let progress: @Sendable (Int) -> Void
    private var body = BoundedWebBody()
    private var mediaType: String?

    init(request: UserSuppliedWebURL, operation: WebReadOperation, progress: @escaping @Sendable (Int) -> Void) {
        self.request = request; self.operation = operation; self.progress = progress
    }
    func channelActive(context: ChannelHandlerContext) {
        guard !operation.isFinished else { context.close(promise: nil); return }
        let headers = HTTPHeaders([("Host", request.hostname), ("User-Agent", "Jarvis-EVO-SourceReader/1.0"),
                                   ("Accept", "text/html, text/plain"), ("Accept-Encoding", "identity"),
                                   ("Connection", "close")])
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: request.requestTarget, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        let written = context.eventLoop.makePromise(of: Void.self)
        written.futureResult.whenFailure { [operation] in operation.finish(.failure($0)) }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: written)
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !operation.isFinished else { return }
        do {
            switch unwrapInboundIn(data) {
            case .head(let head):
                guard mediaType == nil, head.headers.count <= 100 else { throw WebSourceError.invalidResponse }
                mediaType = try WebResponsePolicy.validate(status: Int(head.status.code), fields: head.headers.map { ($0.name, $0.value) })
            case .body(let buffer):
                guard mediaType != nil else { throw WebSourceError.invalidResponse }
                guard buffer.readableBytes <= WebSourceLimits.bodyBytes - body.data.count else { throw WebSourceError.bodyTooLarge }
                try buffer.withUnsafeReadableBytes { try body.append(Data($0)) }
                progress(body.data.count)
            case .end(let trailers):
                guard let mediaType, trailers == nil || trailers?.isEmpty == true else { throw WebSourceError.invalidResponse }
                operation.finish(.success(RetrievedWebBody(url: request.url, mediaType: mediaType, data: body.data)))
            }
        } catch { operation.finish(.failure(error)) }
    }
    func channelInactive(context: ChannelHandlerContext) {
        operation.finish(.failure(WebSourceError.invalidResponse))
        context.fireChannelInactive()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { operation.finish(.failure(error)) }
}

/// Platform certificate evaluation with per-evaluation network fetching disabled and no trust exceptions.
enum WebTLSIdentity {
    static func evaluate(_ trust: SecTrust, hostname: String) -> Bool {
        let policy = SecPolicyCreateSSL(true, hostname as CFString)
        guard SecTrustSetPolicies(trust, policy) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }
}

/// One public error policy, applied at exactly-once transport completion.
enum WebTransportErrorPolicy {
    static func normalize(_ error: Error) -> Error {
        if let error = error as? WebSourceError { return error }
        if error is CancellationError { return error }
        if error is HTTPParserError || error is NIOHTTPDecoderError { return WebSourceError.invalidResponse }
        if let network = error as? NWError, case .posix(let code) = network, code == .ETIMEDOUT { return WebSourceError.timeout }
        // A failed route/connection is not evidence that the entire device is offline.
        if let channel = error as? ChannelError, case .connectTimeout = channel { return WebSourceError.timeout }
        return WebSourceError.transportUnavailable
    }
}
