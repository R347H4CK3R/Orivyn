import Foundation
import Darwin
import dnssd

protocol WebDNSResolving: Sendable {
    func resolve(_ request: UserSuppliedWebURL) async throws -> PublicWebIPv4
}

struct PublicWebDNSResolver: WebDNSResolving {
    private let api: any WebDNSStarting
    private let deadlines: any WebDNSDeadlineScheduling
    private let admission: WebDNSAdmissionPool

    init(api: any WebDNSStarting = SystemWebDNSAPI(), deadlines: any WebDNSDeadlineScheduling = SystemWebDNSDeadlines(),
         admission: WebDNSAdmissionPool = .shared) {
        self.api = api; self.deadlines = deadlines; self.admission = admission
    }

    func resolve(_ request: UserSuppliedWebURL) async throws -> PublicWebIPv4 {
        try Task.checkCancellation()
        if let literal = try? PublicWebIPv4(request.hostname) { return literal }
        let query = WebDNSQuery(host: request.hostname, api: api, deadlines: deadlines, admission: admission)
        let value = try await withTaskCancellationHandler {
            try await query.resolve()
        } onCancel: { query.finish(.failure(CancellationError())) }
        try Task.checkCancellation()
        return value
    }
}

enum WebDNSRecord: Sendable {
    case address(String, moreComing: Bool)
    case failure(WebSourceError)
}

/// The caller serializes creation, callbacks and cancellation on the supplied queue.
/// start may block in operating-system IPC; cancellation must not race that call.
protocol WebDNSStarting: Sendable {
    func start(host: String, queue: DispatchQueue, receive: @escaping @Sendable (WebDNSRecord) -> Void) throws -> any WebDNSService
}
protocol WebDNSService: AnyObject, Sendable { func cancel() }
protocol WebDNSDeadline: Sendable { func cancel() }
protocol WebDNSDeadlineScheduling: Sendable {
    func schedule(after seconds: TimeInterval, action: @escaping @Sendable () -> Void) -> any WebDNSDeadline
}

/// Admission includes completed callers whose OS setup or cleanup is still blocked.
/// No work is queued when capacity is exhausted; a new caller receives .busy immediately.
final class WebDNSAdmissionPool: @unchecked Sendable {
    static let shared = WebDNSAdmissionPool(limit: 2)
    private let lock = NSLock()
    private let limit: Int
    private var outstanding = 0
    init(limit: Int) { self.limit = max(1, limit) }
    func acquire() -> Lease? {
        lock.withLock {
            guard outstanding < limit else { return nil }
            outstanding += 1
            return Lease(pool: self)
        }
    }
    private func release() { lock.withLock { outstanding -= 1 } }
    final class Lease: @unchecked Sendable {
        private let lock = NSLock()
        private var pool: WebDNSAdmissionPool?
        fileprivate init(pool: WebDNSAdmissionPool) { self.pool = pool }
        func release() {
            let owner = lock.withLock { let value = pool; pool = nil; return value }
            owner?.release()
        }
    }
}

/// Caller completion is lock protected, independent of the possibly blocked service queue.
/// Only the service queue owns the API handle, accumulated records and admission lease.
private final class WebDNSQuery: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.jarvisevo.source-dns")
    private let lock = NSLock()
    private let host: String
    private let api: any WebDNSStarting
    private let deadlines: any WebDNSDeadlineScheduling
    private let admission: WebDNSAdmissionPool
    private var outcome: Result<PublicWebIPv4, Error>?
    private var continuation: CheckedContinuation<PublicWebIPv4, Error>?
    private var timer: (any WebDNSDeadline)?
    // Service-queue-only fields:
    private var service: (any WebDNSService)?
    private var lease: WebDNSAdmissionPool.Lease?
    private var addresses: [PublicWebIPv4] = []

    init(host: String, api: any WebDNSStarting, deadlines: any WebDNSDeadlineScheduling, admission: WebDNSAdmissionPool) {
        self.host = host; self.api = api; self.deadlines = deadlines; self.admission = admission
    }
    private var isFinished: Bool { lock.withLock { outcome != nil } }

    func resolve() async throws -> PublicWebIPv4 {
        try await withCheckedThrowingContinuation { continuation in
            let existing = lock.withLock { () -> Result<PublicWebIPv4, Error>? in
                if let outcome { return outcome }
                self.continuation = continuation
                return nil
            }
            if let existing { continuation.resume(with: existing); return }
            // This deadline is installed before setup and runs independently of its queue.
            let deadline = deadlines.schedule(after: 5) { [weak self] in self?.finish(.failure(WebSourceError.timeout)) }
            let alreadyFinished = lock.withLock { () -> Bool in
                guard outcome == nil else { return true }
                timer = deadline
                return false
            }
            if alreadyFinished { deadline.cancel(); return }
            guard let lease = admission.acquire() else { finish(.failure(WebSourceError.busy)); return }
            queue.async { [self, lease] in
                self.lease = lease
                guard !isFinished else { cleanup(); return }
                do {
                    // Retained by this queue closure even if the caller has already completed.
                    service = try api.start(host: host, queue: queue) { [weak self] record in self?.receive(record) }
                    if isFinished { cleanup() }
                } catch {
                    finish(.failure(error as? WebSourceError ?? .transportUnavailable))
                    cleanup()
                }
            }
        }
    }

    func finish(_ result: Result<PublicWebIPv4, Error>) {
        let completion = lock.withLock { () -> (Bool, CheckedContinuation<PublicWebIPv4, Error>?, (any WebDNSDeadline)?) in
            guard outcome == nil else { return (false, nil, nil) }
            outcome = result
            let continuation = continuation
            let timer = timer
            self.continuation = nil; self.timer = nil
            return (true, continuation, timer)
        }
        guard completion.0 else { return }
        completion.2?.cancel()
        // Resume without waiting for DNS setup or DNSServiceRefDeallocate.
        completion.1?.resume(with: result)
        queue.async { [self] in cleanup() }
    }

    private func receive(_ record: WebDNSRecord) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !isFinished else { return }
        switch record {
        case .failure(let error): finish(.failure(error))
        case .address(let literal, let moreComing):
            guard addresses.count < 16 else { finish(.failure(WebSourceError.invalidResponse)); return }
            do { addresses.append(try PublicWebIPv4(literal)) }
            catch { finish(.failure(error)); return }
            if !moreComing, let first = addresses.first { finish(.success(first)) }
        }
    }

    private func cleanup() {
        dispatchPrecondition(condition: .onQueue(queue))
        let handle = service
        service = nil
        handle?.cancel()
        // Never release capacity before setup and serialized deallocation have returned.
        lease?.release(); lease = nil
    }
}

struct SystemWebDNSDeadlines: WebDNSDeadlineScheduling {
    func schedule(after seconds: TimeInterval, action: @escaping @Sendable () -> Void) -> any WebDNSDeadline {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds, execute: item)
        return Token(item: item)
    }
    private final class Token: WebDNSDeadline, @unchecked Sendable {
        let item: DispatchWorkItem
        init(item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }
}

struct SystemWebDNSAPI: WebDNSStarting {
    func start(host: String, queue: DispatchQueue, receive: @escaping @Sendable (WebDNSRecord) -> Void) throws -> any WebDNSService {
        dispatchPrecondition(condition: .onQueue(queue))
        let box = Unmanaged.passRetained(CallbackBox(receive: receive))
        var reference: DNSServiceRef?
        let callback: DNSServiceGetAddrInfoReply = { _, flags, _, error, _, address, _, context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            guard error == kDNSServiceErr_NoError, let address, Int32(address.pointee.sa_family) == AF_INET,
                  flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0 else { box.receive(.failure(.transportUnavailable)); return }
            var raw = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &raw, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { box.receive(.failure(.invalidResponse)); return }
            box.receive(.address(String(cString: buffer), moreComing: flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) != 0))
        }
        // Absolute A-record lookup only. This synchronous API may stall; the caller is independently cancellable.
        let status = DNSServiceGetAddrInfo(&reference, DNSServiceFlags(kDNSServiceFlagsTimeout), 0,
                                          UInt32(kDNSServiceProtocol_IPv4), host + ".", callback, box.toOpaque())
        guard status == kDNSServiceErr_NoError, let reference else {
            if let reference { DNSServiceRefDeallocate(reference) }
            box.release()
            throw WebSourceError.transportUnavailable
        }
        let handle = Handle(reference: reference, box: box, queue: queue)
        guard DNSServiceSetDispatchQueue(reference, queue) == kDNSServiceErr_NoError else {
            handle.cancel()
            throw WebSourceError.transportUnavailable
        }
        return handle
    }
    private final class CallbackBox: @unchecked Sendable {
        let receive: @Sendable (WebDNSRecord) -> Void
        init(receive: @escaping @Sendable (WebDNSRecord) -> Void) { self.receive = receive }
    }
    /// Owned by WebDNSQuery until cancel, or by start until an installation failure is cleaned up.
    private final class Handle: WebDNSService, @unchecked Sendable {
        private var reference: DNSServiceRef?
        private var box: Unmanaged<CallbackBox>?
        private let queue: DispatchQueue
        init(reference: DNSServiceRef, box: Unmanaged<CallbackBox>, queue: DispatchQueue) {
            self.reference = reference; self.box = box; self.queue = queue
        }
        func cancel() {
            dispatchPrecondition(condition: .onQueue(queue))
            guard let reference else { return }
            self.reference = nil
            DNSServiceRefDeallocate(reference)
            box?.release(); box = nil
        }
    }
}
