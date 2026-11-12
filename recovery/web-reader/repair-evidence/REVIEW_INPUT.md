# Independent review: frozen Jarvis-EVO web-source reader

Date: 2026-11-12. Scope: the isolated overlay in `/workspace/shared/Jarvis-EVO-web-work`, not a shipped or integrated feature. Review performed by one reviewer, without additional reviewers. Existing application reference: `/workspace/shared/Jarvis-EVO-recovery-next`.

## Verdict

**Fixes required before application integration or a user-facing entry point.** The public-IP pinning and restricted transport architecture are substantially better than a hostname preflight followed by a second DNS lookup. No confirmed Critical address-validation or certificate-trust bypass was found in this static review. However, four Important correctness/lifecycle issues below need fixes and targeted regression tests. Isolated Mac compilation and test development may proceed now; that is not approval to enable the feature.

The native acceptance gates in `docs/INTEGRATION_PROPOSAL.md:14-22` remain mandatory after correction. This review does not establish Swift compilation, a successful page retrieval, native cancellation safety, on-device networking privacy, or a working local-model summary.

## Reviewed and verified

- Read all eight production Swift files, all five XCTest files (24 authored test methods), all four design/provenance/integration/test reports, package and revision pins, fixture-generation evidence, reference scripts, and relevant pinned NIO/NIOTransportServices source.
- Independently hashed the manifest: `491958ea5d810daa3a66787b2f2b04594ca7a8ac2a376bb5eb943c4f322ffba7`. All 40 listed files matched. The six recorded application contract hashes also matched at review time.
- Reran `PYTHONDONTWRITEBYTECODE=1 python3 scripts/check_reference_fixtures.py`: all six checks passed, including the 18 framing split cases and 12 malformed-frame cases against the existing llhttp executable. These checks do not run the production Swift implementation.
- Inspected the test DER certificate with OpenSSL. It is a self-signed CA certificate for `public.example.com`, valid from November 12, 2026 to November 9, 2036, used only in tests. The test verification date is January 1, 2027. It contains no AIA/OCSP fetch fixture.
- Confirmed neither `swift` nor `xcodebuild` is available. Did not rerun the public network probe; its recorded attempt failed DNS before any connection. No successful public retrieval is claimed.
- Used small, explicitly non-Swift reference calculations to demonstrate the context-trimming and inline-separator consequences below. They are reasoning aids, not native test results.
- No application or frozen-overlay source, index, refs, or CI was modified. No dependency installation, push, CI trigger, or user contact was performed. This report is outside the frozen tree.

## Strengths

1. **Actual connection address is pinned.** `PinnedWebTransport.swift:43-45` uses `SocketAddress(ipAddress:)` followed by `connect(to:)`, never hostname connect. In pinned NIO, `SocketAddresses.swift:349-379` parses numeric bytes with `inet_pton`; NIOTS `SocketAddress+NWEndpoint.swift:61-64` creates an `.ipv4` endpoint; `StateManagedNWConnectionChannel.swift:128-160` passes that endpoint to `NWConnection`. This avoids the rejected preflight/re-resolution race.
2. **TLS identity is not reduced to SNI alone.** `PinnedWebTransport.swift:59-72,197-201` requires TLS 1.2+, uses the original hostname, evaluates an SSL server policy against platform trust, checks setup return codes, and never installs production test anchors or accepts failed trust. Apple documents the server-name option as overriding the peer-certificate verification name. Tickets, resumption and renegotiation are explicitly disabled.
3. **Restricted outbound scope is clear in source.** URL validation rejects credentials, queries, fragments, non-443 ports, private/reserved IPv4 ranges and ambiguous numeric authority spellings. DNS asks for A records with an absolute name; the selected public literal is used once. HTTP contains only a GET path, original Host and generic reader headers. There is no cookie/session/cache/authentication integration, redirect following, retry, JavaScript, DOM renderer, subresource loader, remote-model call or conversation/file access.
4. **Useful independent bounds exist.** The pre-parser wire handler caps initial headers at 16 KiB and total plaintext wire input at 288 KiB. The production body accumulator caps decoded body bytes at 256 KiB. Compression is rejected rather than decompressed without a bound. NIO/llhttp supplies framing; status and framing policy rejects redirects, access challenges, informational responses and nonempty trailers. HTML has bounded input, tokens, tags, depth and UTF-8 output.
5. **Provenance is appropriately limited.** Snapshot UUIDs, exact validated URLs, retrieval time and truncation metadata are maintained. Citation lookup cannot invent a destination for an unknown ID. Source text remains explicitly untrusted, and the docs correctly do not present JSON framing as a prompt-injection guarantee. No model is called in this overlay.
6. **Evidence and release claims are restrained.** Dependency provenance and licenses are recorded, native resolve is not falsely claimed, the app remains untouched, and unsupported site classes are disclosed. The selected exact dependency versions meet the inspected manifests' declared minimums. Neither source size nor a Python probe is passed off as installed app size or iOS execution.

## Critical findings

None confirmed by the available static evidence. This does not mean the unexecuted native security gates passed.

## Important findings

### I1. Default multi-source context reduction can discard almost all sources

**Location:** `JarvisEVO/Services/WebSources/WebSourceContext.swift:35-42`, with citations retained at `45-47`.

Each iteration chooses the longest text and removes the entire current JSON overage from that one source. For three equal 16,384-byte texts and the default 6,000-byte budget, the first two chosen texts become empty. A reference calculation with short metadata retained text lengths `[0, 0, 5189]`; Swift tie ordering may choose a different survivor, but the same starvation follows from the algorithm. All three source IDs still remain in the payload and citation registry.

**Impact:** An ordinary three-page research request can provide substantive evidence from only one page to the future local model, losing disagreements or corroboration while appearing to have three sources. The truncation flags disclose loss, but do not make this a useful multi-source allocation.

**Fix:** Reserve and validate fixed metadata first, allocate a fair minimum text allowance across all included sources, then distribute unused budget without repeatedly zeroing one long source. Respect actual JSON escaping and UTF-8 bytes. If meaningful evidence from every requested source cannot fit, fail clearly or explicitly identify omitted sources rather than quietly retaining empty evidence entries as normal sources.

**Required tests:** Three equal long sources, unequal lengths, quotes/control escapes, multibyte text, long URLs and budgets barely above metadata. Assert the total encoded budget and a nonempty reasonable excerpt from every included source, plus accurate truncation/omission flags.

### I2. DNS timeout and cancellation do not cover synchronous query setup

**Location:** `JarvisEVO/Services/WebSources/WebDNSResolver.swift:35-51,56-60`; transport deadline begins only after DNS at `PinnedWebTransport.swift:15-20`. Related claim: `docs/WEB_SOURCE_DESIGN.md:20`.

`DNSServiceGetAddrInfo` runs synchronously on the operation's private serial queue. The five-second timer is installed only after it returns, and cancellation is also queued behind that call. If setup stalls, neither the timer nor cancellation can finish the continuation. This is not merely a hypothetical permanently broken OS: Apple's published DNS client implementation performs synchronous daemon IPC during this API and has a 60-second client response timeout (`dnssd_clientstub.c`, `DNSSD_CLIENT_TIMEOUT` and `deliver_request`). That source is supporting API implementation evidence, not a measurement of iOS 26.

**Impact:** A resolver startup stall can keep the source operation and its `busy` state outstanding far beyond the advertised five seconds, including after the user cancels. Moving the timer earlier on the same blocked queue alone would not fix this.

**Fix:** Separate bounded caller completion/deadline state from potentially blocking resolver setup. Keep DNSServiceRef creation, callbacks and deallocation on their required serialized queue; never deallocate it concurrently to force cancellation. Retain the operation until setup returns, then immediately clean up if it was already cancelled/timed out. Bound outstanding abandoned setup work so repeated actions cannot accumulate threads/operations. If a strict startup bound cannot be provided, change both the contract and user-visible behavior explicitly rather than claiming one.

**Required tests:** An injectable DNS API shim that stalls initial setup beyond the deadline, cancellation while setup is blocked, late successful setup after timeout, callback/cancel races and exact-once continuation/deallocation checks. The current test files contain no DNS resolver tests.

**Primary source:** [Apple DNS client implementation](https://raw.githubusercontent.com/apple-oss-distributions/mDNSResponder/main/mDNSShared/dnssd_clientstub.c), especially the 60-second constant, `DNSServiceGetAddrInfoInternal`, and `deliver_request`; [Apple DNS-SD header](https://raw.githubusercontent.com/apple-oss-distributions/mDNSResponder/main/mDNSShared/dns_sd.h) requires deallocation on the dispatch queue used for callbacks.

### I3. Unconditional HTML tag separators alter source words and numbers

**Location:** `JarvisEVO/Services/WebSources/WebTextExtractor.swift:108-111,124-133`, with `TextWriter.separator/append` at `31-43`.

The extractor inserts a pending space at every opening and closing element, including inline `b`, `span`, `em` and `a`. Valid HTML `<p>The rate is 0.<b>5</b>%.</p>` therefore becomes `The rate is 0. 5 %.`. Similarly, a word split across an inline emphasis tag acquires spaces. The existing tests have no such inline-adjacency fixture.

**Impact:** This changes factual source text before citation and synthesis. Numbers, units, identifiers and words can be misread. This is separate from the intentional refusal to implement HTML5 optional-end-tag recovery: the example is well-formed supported markup.

**Fix:** Preserve text adjacency across ordinary inline elements; add separators for appropriate block/break boundaries and deliberate removal of hidden/raw content. Keep the bounded, non-rendering design. Do not introduce a browser or network-aware parser to fix this.

**Required tests:** Numeric punctuation, words split by inline tags, inline links/emphasis, adjacent block elements, `br`, and removed hidden/script content. Assert exact extracted text.

### I4. Post-connect transport failures bypass the public error policy

**Location:** `JarvisEVO/Services/WebSources/PinnedWebTransport.swift:45,76-82,167,192`; `WebSourceReader.swift:59-62`.

Only bootstrap failure uses `Self.map`. Inbound network/parser failures and request-write failures finish with the original error. A post-connect `NWError.posix(.ENETDOWN)` therefore does not take the mapping path: `readMany` collapses it to `transportUnavailable`, while `read` exposes a raw platform error. Parser failures similarly lose the intended `invalidResponse` classification in batches. This can be tested by injecting an error into the embedded pipeline without a real network.

**Impact:** The same failure is reported differently depending on when it occurs and whether one or several URLs were requested. Wi-Fi loss during a body can become an unexplained retrieval-unavailable message, and malformed HTTP is not classified consistently. Also, `.ENETUNREACH` or `.ENOTCONN` alone is not proof that the whole device is offline, so the current connection-error mapping can overstate offline status.

**Fix:** Normalize every terminal transport error at one boundary, preserve `CancellationError` and already classified `WebSourceError`, distinguish malformed response from network/handshake failure, and use a truthful reachability/unavailable message unless offline is actually known. Keep detailed diagnostics separate from user-safe error text and do not log sensitive URL paths by default.

**Required tests:** Inject identical network and parser errors before/after activation and during request write/body receive; assert consistent single/batch outcomes, cancellation precedence and no partial source result.

## Minor findings

### M1. Title truncation has no observable flag

**Location:** `JarvisEVO/Services/WebSources/WebTextExtractor.swift:54,138`; `WebSource.swift:11-13`.

The 240-byte title writer records truncation internally, but the result only exposes `body.truncated`. A shortened title can therefore look complete to citation UI and model context. Add a title-truncation flag or an explicit bounded display indicator, with Unicode tests. This does not defeat the byte limit.

### M2. Header/wire failures use a misleading body-size message

**Location:** `PinnedWebTransport.swift:129-143`; `WebSource.swift:45`.

A header exceeding 16 KiB, or excessive chunk/trailer overhead, is reported as exceeding the 256 KiB retrieval limit. Use a distinct response-limit error or wording covering header/wire/body limits. Keep the early rejection.

## Trust and certificate-fetch assessment

The callback copies the provided trust object, replaces its policy with the original-host SSL server policy, disables network fetching before evaluating, and returns the evaluation result. I found no production trust exception, permissive completion, local anchor injection, or certificate-name fallback. [Apple's server-name documentation](https://developer.apple.com/documentation/security/sec_protocol_options_set_tls_server_name(_:_:).md) supports the hostname override; [SecTrustSetNetworkFetchAllowed](https://developer.apple.com/documentation/security/sectrustsetnetworkfetchallowed(_:_:).md) and [TN2232](https://developer.apple.com/library/archive/technotes/tn2232/_index.html) support disabling per-trust network access.

That is still not proof of all on-device network effects. Apple's published trust implementation separately permits background revocation-database maintenance even when per-evaluation network access is disabled. Do not expand the promise into “Security.framework causes absolutely no OS network traffic.” The relevant safety gate remains: no unvalidated certificate AIA/OCSP destination is contacted for this reader, no request data is sent to other destinations, and actual platform trust is enforced. A no-AIA self-signed unit certificate cannot prove that gate. Use controlled AIA/OCSP endpoints and packet/process-aware instrumentation on the target OS, without weakening production trust to make the test pass. [Apple revocation implementation](https://raw.githubusercontent.com/apple-oss-distributions/Security/main/trust/trustd/SecRevocationServer.c) distinguishes per-evaluation revocation fetch permission from background database refresh.

## Exact declined-to-judge list

The following remain **unverified**, rather than passed or inferred from the C/Python checks:

1. Swift 6 compile/type checking, Apple SDK availability/import details, strict concurrency diagnostics, SwiftPM native dependency resolution and the actual generated lock file.
2. Execution and pass status of all 24 native tests, including fixture trust behavior; no XCTest code ran in this review.
3. Any real native public-page retrieval, original Host/SNI and certificate identity as observed on wire, TLS version negotiation, default trust-store acceptance, missing-chain rejection, bad/expired/untrusted certificate rejection, and absence of client-certificate use/session resumption.
4. Actual AIA/OCSP/network behavior of iOS 26, background Security.framework traffic, VPN/proxy/network-extension effects and physical routing. Static address pinning proves the destination handed to the connection API, not the eventual physical route.
5. DNS runtime record batching, stale callbacks, rebinding fixtures, startup latency, reference lifetime, timeout/cancellation races and absence of leaks/double-resume on target platforms.
6. End-to-end transport deadline/cleanup behavior during TLS, bootstrap cancellation, write failures and event-loop shutdown; no claim that all OS buffers/work cease exactly when the task completes.
7. Complete production NIO pipeline behavior for bytewise EOF framing, 100/101, oversized trailers/chunk extensions, field-count boundaries, duplicate/ambiguous framing, compressed responses, interruptions and timeout races. Some cases have authored tests, but neither those nor additional native fixtures ran.
8. Exhaustive extraction correctness, adversarial CPU/allocation behavior and cancellation latency. Input/output bounds are inspectable; real process memory and energy bounds are not established.
9. Real local-model summarization quality, prompt-injection resistance, claim-to-citation correctness, context-window integration and absence of remote fallback in an integrated application. This overlay prepares data only.
10. UI consent/disclosure, button wiring, per-source progress/error display, stale-session result suppression, local-only provider selection, history/persistence behavior and full-app regressions. They are proposed, not implemented here.
11. iPhone/iOS 26 device/simulator compatibility, IPv6-only-network behavior, App Store acceptance, installed binary size, startup/memory/energy delta and broad real-site usefulness under the intentionally strict page restrictions.
12. An exhaustive security-advisory/legal-license audit of all transitive dependencies. Recorded source/version/license evidence was checked, but that is not an audit of every upstream line or current advisory.

## Recommended next sequence

1. Correct I1-I4 in a new reviewable overlay revision; add the specified focused tests. Address the two small diagnostic/metadata issues while there.
2. Refresh hashes and obtain targeted review of the changed implementation, especially DNS lifetime/completion ownership. Do not modify the frozen snapshot in place as if it were the reviewed revision.
3. Resolve and compile the isolated harness on a Mac with the exact pins, run all tests plus the missing DNS/transport fixtures, and retain result bundles and full diagnostics.
4. Run controlled native DNS/TLS/network-privacy tests and an actual approved public-page read, then integrate only into a disposable app copy for complete iOS 26 regression gates and measured footprint.
5. Keep public claims narrow: explicit user-supplied URL reading, not web search; local summaries only after actual integration; no claim of successful retrieval, native safety verification or shipping based on this review.
