# API and dependency provenance

Apple API documentation inspected on 2026-11-12:

- https://developer.apple.com/documentation/security/sec_protocol_options_set_tls_server_name(_:_:).md states that the override is the server name used when verifying the peer certificate, replacing the endpoint name. This is stronger than an SNI-only claim.
- https://developer.apple.com/documentation/security/secpolicycreatessl(_:_:) documents requiring the supplied hostname to match the leaf certificate.
- https://developer.apple.com/documentation/security/sec_protocol_options_set_tls_resumption_enabled(_:_:) and https://developer.apple.com/documentation/security/sec_protocol_options_set_tls_tickets_enabled(_:_:) document disabling TLS reuse.
- https://developer.apple.com/documentation/dnssd/dnsservicesetdispatchqueue(_:_:) documents a serial dispatch queue for DNSServiceRef callbacks; do not also call DNSServiceProcessResult.
- https://developer.apple.com/documentation/dnssd/dnsservicegetaddrinfo(_:_:_:_:_:_:_:) provides the cancellable DNSServiceRef API.
- https://mas.owasp.org/MASTG/best-practices/MASTG-BEST-0043/ records the important fact that Network.framework lies outside ATS. The transport sets its TLS minimum explicitly.

Exact official Apple repositories, release tags, commit hashes and selected source/license hashes are recorded in evidence/DEPENDENCIES.json. All five refs were retrieved from official public GitHub repositories. No software from another vendor/source was installed. Downloaded sources were inspected without running their package build scripts. Only the bundled llhttp C parser was compiled for independent framing probes.

Pinned dependencies: NIOTransportServices 1.26.0; SwiftNIO 2.83.0; Atomics 1.2.0; Collections 1.1.4; System 1.4.0. NIOTransportServices requires NIO >=2.83.0. NIO requires Atomics >=1.1.0, Collections >=1.1.0 and System >=1.4.0. The selected versions meet those declared bounds. Native SwiftPM resolution remains unexecuted. The checked-in Package.resolved is a hand-recorded revision lock to verify, not evidence of native resolution.

Licenses: NIO/NIOTransportServices Apache-2.0; Atomics/Collections/System Apache-2.0 with Swift Runtime Library Exception; bundled llhttp 9.2.1 MIT. Complete texts are under ThirdPartyNotices. The original repositories remain unmodified under evidence/upstream for inspection, not app bundling.

Inspected implementation contracts:

- NIOTransportServices NIOTSConnectionBootstrap.connect(to: SocketAddress) calls channel.connect(to: address), whereas connect(host:port:) creates a hostname endpoint. Production deliberately uses only the former after validation.
- NIOTSConnectionBootstrap.tlsOptions accepts NWProtocolTLS.Options.
- NIOTSChannelOptions exposes maximumReceiveLength, waitForActivity and enablePeerToPeer.
- NIOHTTP1 HTTPResponseDecoder supports informationalResponseStrategy.forward and uses llhttp, with 80 KiB upstream individual-field limits. The application adds a stricter 16 KiB initial-header gate before this parser and a 288 KiB total wire gate.
- NIOHTTP1's ordinary client pipeline includes HTTPRequestEncoder, ByteToMessageHandler(HTTPResponseDecoder) and NIOHTTPRequestHeadersValidator. The draft uses those same components explicitly to forward/reject informational responses.

Security and API semantics were researched, but no Apple-platform compilation or behavior is claimed from this source inspection.
