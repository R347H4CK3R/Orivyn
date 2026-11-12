# Bounded web source foundation

Status: isolated implementation draft, not integrated, not native-compiled, and not release-ready. This overlay adds explicit-user-invoked page retrieval, text extraction, provenance and bounded multi-source context. It does not add search, automatic browsing, UI, persistence, AppModel wiring, model execution, or remote-model transmission. No existing application file is modified.

## Chosen approach and rejected alternatives

The coordinator selected Apple SwiftNIO plus NIOTransportServices with pinned permissive dependencies. A bounded DNSServiceGetAddrInfo A-record lookup produces a validated canonical public IPv4 literal. NIOTSConnectionBootstrap.connect(to: SocketAddress) connects to that literal, while the original hostname remains the HTTP Host and TLS certificate identity. The application does not pass the original hostname back to the socket connector. This avoids a second DNS lookup and the usual preflight/rebinding race.

URLSession with a hostname preflight was rejected because its connection DNS lookup cannot be tied to the validated result through a documented pinning hook. An IP-literal-only URLSession reader was rejected as too limited for ordinary websites. A bespoke HTTP parser was rejected in favor of NIOHTTP1's llhttp-backed parser. There is no silent URLSession fallback, hand-written TLS, third-party proxy, account requirement, or paid key.

Apple explicitly documents sec_protocol_options_set_tls_server_name as setting the name used to verify the peer certificate, overriding the endpoint name. The implementation additionally evaluates the original hostname using SecPolicyCreateSSL and SecTrustEvaluateWithError against the platform trust store. It never adds anchors, accepts failed trust, or disables certificate checks. Network fetches during trust evaluation are disabled to avoid following certificate AIA/OCSP URLs to unvalidated destinations. This may reject servers that omit required intermediates. TLS minimum is 1.2; tickets, resumption and renegotiation are disabled. Network.framework is outside ATS, so no ATS-equivalence claim is made.

## Consent and privacy boundary

Only an explicit public URL supplied by the user may create UserSuppliedWebURL. The future UI must display the exact URL and say that the destination receives the user's network IP, hostname/path, and a generic user agent. DNS resolution sends only the explicit hostname through the operating system resolver. Never derive requests from conversation, documents, memory, model output, page links or inferred searches. Never send source context to a remote provider as a side effect. No cookie jar, credential store, client identity, HTTP cache, Referer, browser session, connection pool, TLS resumption, subresources, JavaScript, redirects, automatic retries or refreshes are used. A redirect is an error, not a new authorized destination. HTTP 401/403/407/429 stop that request. The service does not bypass site restrictions or navigate login, billing, gated or CAPTCHA flows.

## Limits and resource accounting

- HTTPS port 443; ASCII host/path spelling up to 2,048 bytes; no credentials, query or fragment. Percent-encoded UTF-8 paths are accepted after control-character checks. Canonical public IPv4 literals or validated multi-label DNS names only. Local/reserved host suffixes are rejected.
- DNS requests only A records, appends a root dot to avoid search-domain expansion, accepts at most 16 records, validates every returned address used before connection, and has a 5-second cancellation/deadline. No IPv6, mapped, transition, DNS64 or local-network fallback.
- One source operation at a time; one to three unique URLs per explicit batch; minimum two seconds between starts. No automatic retry. Each source gets one selected address and one connection attempt.
- 10-second connect timeout and 30-second transport deadline after DNS. One 8 KiB maximum Network.framework receive completion, 16 KiB initial HTTP header budget, 100 fields, 288 KiB total plaintext HTTP wire budget including chunk/trailer overhead, 256 KiB decoded body budget. NIO performs HTTP framing, including chunked bodies. Informational responses, non-200 responses, upgrade flows, ambiguous lengths and nonempty trailers are rejected.
- Only identity Content-Encoding. Compressed responses are rejected before any decompression because no decompressor exists in this pipeline. Advertised content length and accumulated body bytes are checked separately. The wire budget bounds bytes entering the parser, not encrypted TLS overhead or OS buffers. OS TLS/DNS internals and allocation overhead are not claimed to fit this byte budget. These are application input limits, not a process memory proof.
- UTF-8 text/html or text/plain only; 16 KiB extracted text, 240-byte title, 10,000 HTML tokens, 4 KiB tag, 64-element stack. UTF-8 scalar boundaries are preserved; a truncated combining sequence is possible and is not claimed to preserve whole graphemes.

## Extraction and prompt injection

The strict linear HTML tokenizer never loads a DOM or renders HTML. It discards attributes and executable/foreign/hidden elements, extracts title separately, decodes a small safe entity set and numeric Unicode scalars, and normalizes whitespace/control characters. It rejects malformed/deep markup rather than reproducing the HTML5 recovery algorithm. Optional-end-tag documents, CSS visibility, unknown named entities, script-created pages and some ordinary HTML will be incomplete or unsupported. The extracted text must never be fed to a web view as markup. Unknown entity spellings remain text.

Text and titles remain untrusted and can contain false claims or malicious model instructions. JSON framing and synthesis instructions reduce confusion but are not a prompt-injection guarantee. Future synthesis must be local, tool-free, explicitly label untrusted source data, and cite only IDs resolved through the retrieved snapshot registry. Citation links are provenance, not proof. Text truncation and context truncation have separate flags. No search results or summaries are fabricated.

## Scope and limitations

This is a safe-address-pinned, limited source reader design, not general browsing or search. HTTPS hostnames with public A records are supported in the draft. IPv6-only sites, query-bearing URLs, redirects, compressed-only pages, non-UTF-8 text, PDFs, gated pages and JavaScript pages are intentionally unsupported. OS/VPN/NAT routing and OS DNS infrastructure are outside application control; the promise is a validated public destination passed to the connection API, not proof of physical network topology.

The app's existing local-provider contract takes GenerationRequest messages/systemPrompt and a bounded context window. Integration must budget these sources together with chat history, not append them after trimming. WebSourceContext prepares at most 6,000 UTF-8 bytes by default, preserving metadata and explicitly flagging text reduction; it does not execute synthesis.

## Implementation plan and rulings

1. Author policy/parser/reader tests first; the actual Swift command is unavailable, so no executed RED/GREEN claim is made.
2. Build isolated pure source types, strict URL/IP policy, bounded tokenizer, provenance/context and serial reader.
3. Follow the coordinator's selected pinned-host NIO transport, verify upstream APIs and licenses, and author framing/cancellation/certificate tests. Transport tests were expanded after the architecture changed; this is not presented as verified TDD.
4. Run independent upstream C framing and Python fixture/provenance checks; record native/toolchain and real-read blockers honestly.
5. Require fresh review, native compile/test and iPhone transport instrumentation before any integration or release.

Rulings: choose IPv4-only rather than an unreviewed IPv6 special-range policy; reject compression rather than claim a false decompression bound; reject redirects rather than expand consent; strict HTML may reject real pages rather than execute a browser; use independent check results only for the exact code they exercised.
