import Foundation
import Darwin
import dnssd

protocol WebDNSResolving: Sendable {
    func resolve(_ request: UserSuppliedWebURL) async throws -> PublicWebIPv4
}

struct PublicWebDNSResolver: WebDNSResolving {
    func resolve(_ request: UserSuppliedWebURL) async throws -> PublicWebIPv4 {
        try Task.checkCancellation()
        if let literal = try? PublicWebIPv4(request.hostname) { return literal }
        let query = WebDNSQuery(host: request.hostname)
        return try await withTaskCancellationHandler {
            try await query.resolve()
        } onCancel: { query.cancel() }
    }
}

/// DNSServiceRef, continuation and timer are owned by this private serial queue.
/// Only A records are requested; an explicit literal is handed to the connector, never the hostname.
private final class WebDNSQuery: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.jarvisevo.source-dns")
    private let host: String
    private var reference: DNSServiceRef?
    private var continuation: CheckedContinuation<PublicWebIPv4, Error>?
    private var timeout: DispatchWorkItem?
    private var finished = false
    private var cancelled = false
    private var addresses: [PublicWebIPv4] = []
    init(host: String) { self.host = host }

    func resolve() async throws -> PublicWebIPv4 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                self.continuation = continuation
                guard !cancelled else { finish(.failure(CancellationError())); return }
                let callback: DNSServiceGetAddrInfoReply = { _, flags, _, error, _, address, _, context in
                    guard let context else { return }
                    let operation = Unmanaged<WebDNSQuery>.fromOpaque(context).takeUnretainedValue()
                    operation.receive(flags: flags, error: error, address: address)
                }
                // A trailing dot prevents local search-domain expansion. No multicast browsing is used.
                let status = DNSServiceGetAddrInfo(&reference, DNSServiceFlags(kDNSServiceFlagsTimeout),
                                                  0, UInt32(kDNSServiceProtocol_IPv4), host + ".", callback,
                                                  Unmanaged.passUnretained(self).toOpaque())
                guard status == kDNSServiceErr_NoError, let reference else { finish(.failure(WebSourceError.transportUnavailable)); return }
                guard DNSServiceSetDispatchQueue(reference, queue) == kDNSServiceErr_NoError else { finish(.failure(WebSourceError.transportUnavailable)); return }
                let timer = DispatchWorkItem { [weak self] in self?.finish(.failure(WebSourceError.timeout)) }
                timeout = timer
                queue.asyncAfter(deadline: .now() + 5, execute: timer)
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            cancelled = true
            if continuation != nil { finish(.failure(CancellationError())) }
        }
    }

    private func receive(flags: DNSServiceFlags, error: DNSServiceErrorType, address: UnsafePointer<sockaddr>?) {
        guard !finished else { return }
        guard error == kDNSServiceErr_NoError, let address, Int32(address.pointee.sa_family) == AF_INET,
              flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0 else { finish(.failure(WebSourceError.transportUnavailable)); return }
        guard addresses.count < 16 else { finish(.failure(WebSourceError.invalidResponse)); return }
        let ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var raw = ipv4.sin_addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &raw, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { finish(.failure(WebSourceError.invalidResponse)); return }
        do { addresses.append(try PublicWebIPv4(String(cString: buffer))) }
        catch { finish(.failure(error)); return }
        if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0 {
            guard let first = addresses.first else { finish(.failure(WebSourceError.transportUnavailable)); return }
            finish(.success(first))
        }
    }

    private func finish(_ result: Result<PublicWebIPv4, Error>) {
        guard !finished else { return }
        finished = true
        timeout?.cancel(); timeout = nil
        if let reference { DNSServiceRefDeallocate(reference); self.reference = nil }
        let completion = continuation
        continuation = nil
        completion?.resume(with: result)
    }
}
