import Foundation

protocol WebSourceTransport: Sendable {
    func retrieve(_ request: UserSuppliedWebURL, progress: @escaping @Sendable (Int) -> Void) async throws -> RetrievedWebBody
}

enum WebSourceProgress: Sendable, Equatable {
    case waiting, connecting(URL), receivedBytes(Int), extracting, finished(UUID)
}

struct WebSourceOutcome: Sendable {
    let requestedURL: URL
    let source: WebSource?
    let error: WebSourceError?
}

/// Serial, in-memory reads only. One explicit batch contains at most three URLs. No retries, cache or history.
actor WebSourceReader {
    private let transport: any WebSourceTransport
    private let minimumInterval: Duration
    private let now: @Sendable () -> Date
    private var busy = false
    private var lastRequest: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    init(transport: any WebSourceTransport = PinnedWebTransport(), minimumInterval: Duration = .seconds(2),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.minimumInterval = max(.zero, minimumInterval)
        self.now = now
    }

    func read(_ request: UserSuppliedWebURL, isOnline: Bool?,
              progress: @escaping @Sendable (WebSourceProgress) -> Void = { _ in }) async throws -> WebSource {
        try Task.checkCancellation()
        guard !busy else { throw WebSourceError.busy }
        guard isOnline != false else { throw WebSourceError.offline }
        busy = true
        defer { busy = false }
        return try await perform(request, progress: progress)
    }

    func readMany(_ requests: [UserSuppliedWebURL], isOnline: Bool?,
                  progress: @escaping @Sendable (WebSourceProgress) -> Void = { _ in }) async throws -> [WebSourceOutcome] {
        try Task.checkCancellation()
        guard !busy else { throw WebSourceError.busy }
        guard isOnline != false else { throw WebSourceError.offline }
        guard !requests.isEmpty, requests.count <= WebSourceLimits.sources,
              Set(requests.map(\.url)).count == requests.count else { throw WebSourceError.tooManySources }
        busy = true
        defer { busy = false }
        var results: [WebSourceOutcome] = []
        for request in requests {
            try Task.checkCancellation()
            do {
                let source = try await perform(request, progress: progress)
                results.append(WebSourceOutcome(requestedURL: request.url, source: source, error: nil))
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                results.append(WebSourceOutcome(requestedURL: request.url, source: nil,
                                                error: error as? WebSourceError ?? .transportUnavailable))
            }
        }
        return results
    }

    private func perform(_ request: UserSuppliedWebURL, progress: @escaping @Sendable (WebSourceProgress) -> Void) async throws -> WebSource {
        if let lastRequest {
            let deadline = lastRequest.advanced(by: minimumInterval)
            if clock.now < deadline { progress(.waiting); try await clock.sleep(until: deadline) }
        }
        try Task.checkCancellation()
        lastRequest = clock.now
        progress(.connecting(request.url))
        let body = try await transport.retrieve(request) { progress(.receivedBytes($0)) }
        try Task.checkCancellation()
        guard body.url == request.url else { throw WebSourceError.redirectBlocked }
        progress(.extracting)
        let text = try WebTextExtractor.extract(body.data, mediaType: body.mediaType)
        try Task.checkCancellation()
        let source = WebSource(id: UUID(), originalURL: request.url, finalURL: body.url, retrievedAt: now(),
                               mediaType: body.mediaType, receivedBodyBytes: body.data.count,
                               title: text.title, titleTruncated: text.titleTruncated, text: text.text, textTruncated: text.truncated)
        progress(.finished(source.id))
        return source
    }
}
