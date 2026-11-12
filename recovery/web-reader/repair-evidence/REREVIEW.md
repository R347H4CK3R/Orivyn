# Scoped independent re-review: web-reader repair

Date: 2026-11-12. Reviewer: the original independent reviewer. Scope: repairs to I1-I4 and M1-M2, their tests, and repair-induced regressions, with particular attention to DNS lifetime, cancellation and admission. This is not a fresh unrelated audit or a native execution report.

## Scoped verdict

**The six original findings are addressed at source-review level. No new Critical or Important blocker was found in this repair scope. Proceed to isolated native validation.**

This clears the prior source-review objection to progressing the repaired design. It does not approve enabling the feature, copying it into the active application candidate, or describing it as working native retrieval. First resolve/compile/test the isolated package on a Mac. Only after that succeeds, use a disposable app copy for the iOS 26 acceptance gates. All runtime/security gates below remain open.

## Reviewed identity and executed checks

- Repaired tree: `/workspace/shared/Jarvis-EVO-web-repair-work`.
- Repaired `DELIVERABLE_SHA256.json`: `58fda038576ecfb51c799672ae4c728eebbb4213cdab75bf55c3d1dfcf89db68`; all 42 entries match.
- Original `DELIVERABLE_SHA256.json`: `491958ea5d810daa3a66787b2f2b04594ca7a8ac2a376bb5eb943c4f322ffba7`; all 40 original entries still match.
- All 40 before-snapshot entries, 42 after-snapshot entries and 94 `PACKAGE_SHA256.json` entries match. All 13 `CHANGES.json` records match the actual before/after files. Independently reconstructed the unified diff from those snapshots and confirmed it exactly matches `FOCUSED.patch`.
- Archive `/workspace/shared/Jarvis-EVO-web-repair-package.tar.gz` hashes to `f48841c310c4902c41c6c906ead8a43c86c194e661693ce9fb5134d4866920b9`, matching the supplied identity. This report was added afterward and is not represented as part of that pre-existing archive or its manifest.
- Read the repair report, focused changes, revised production files and new/changed tests. Reviewed relevant pinned NIO encoder behavior for the `IOData` test correction and write-failure fixture.
- Reran the six existing independent Python/C checks successfully, including the 30 upstream llhttp framing cases. They do not execute any repaired Swift source.
- Ran a non-Swift reference calculation over 500 varied allocation inputs to inspect the revised budgeting logic: 381 admitted cases retained every minimum excerpt within the modeled encoded budget; 119 insufficient-budget cases were rejected. This is not evidence of native `JSONEncoder` or Swift execution.
- Counted 37 authored native test methods in seven files. Neither `swift` nor `xcodebuild` is available; native tests and compilation remain unexecuted. The recorded RED/final attempts both failed to start. No public retrieval probe was rerun.
- No source, dependency, project, index, refs, CI, original freeze or active application was modified. The only review write is this requested report.

## Disposition of original findings

### I1: fair source-context allocation — addressed in source

`JarvisEVO/Services/WebSources/WebSourceContext.swift:34-75` reserves metadata with the larger `false` truncation spelling, reserves a valid-scalar prefix of up to 256 UTF-8 bytes from each nonempty source, then shares spare encoded-byte capacity and redistributes unused allowances. It binary-searches prefixes against actual encoded string cost and performs a final full-payload size check.

The former behavior of emptying two long sources is removed. Metadata plus minimum excerpts that do not fit now fails explicitly. Accounting for JSON escapes is deliberate; changing a truncation flag to `true` reduces rather than increases the reserved metadata cost. Scalar-boundary slack may leave a few bytes unused, which is safe and not a material regression.

Relevant new tests: `Tests/WebSourceRepairTests.swift:9-44` cover equal long sources, unequal/escaped/Unicode text, and metadata-heavy budgets. Native execution remains required.

### I2: independent DNS caller completion and bounded abandoned work — addressed in source

`WebDNSResolver.swift:96-142` separates caller outcome/continuation/deadline from the queue that can block in OS DNS setup. The deadline is scheduled before setup. Timeout/cancellation wins the lock-protected outcome, cancels the timer outside that lock, resumes the caller without awaiting DNS teardown, and queues serialized cleanup.

`WebDNSResolver.swift:47-71,112-124,157-164` adds a shared two-slot pool. A lease covers both active work and work whose caller already completed while OS setup/cleanup remains outstanding. It is not released when the caller returns. Cleanup clears the stored handle before cancellation and releases the lease only after cancellation returns. No OS setup is admitted once both slots are occupied.

The revised documentation correctly distinguishes scheduler-based caller completion from immediate termination of OS work or a hard real-time guarantee. Pool saturation while two OS calls are stuck is a deliberate bounded failure mode, not a reason to recreate unlimited resolver instances or retry automatically.

Detailed ownership analysis follows below. Runtime proof is still required.

### I3: inline adjacency — addressed in source

`WebTextExtractor.swift:58,108-135` restricts separators to enumerated block/break elements and deliberately removed content. Ordinary `b`, `em`, `span`, `i` and `a` boundaries preserve adjacent text. The original numeric and split-word examples are fixed by inspection, without changing the strict non-rendering parser or introducing network-aware extraction.

`Tests/WebSourceRepairTests.swift:46-54` adds exact numeric, word, inline-link, block, break and removed-content expectations. The intentionally limited HTML/CSS semantics remain as previously disclosed.

### I4: terminal error normalization — addressed in source

`PinnedWebTransport.swift:97-107,199-209` applies one normalization function at the exactly-once operation completion boundary. Bootstrap, request-write, parser and body errors now converge there. Classified source errors and cancellation are preserved; parser failures become `invalidResponse`; known timeout forms become `timeout`; route/connection failures do not falsely assert that the device is offline.

The preflight known-offline check in `WebSourceReader` remains unchanged. The revised transport tests exercise pre/post-activation, write and partial-body paths, plus single/batch handling without returning partial sources (`Tests/WebHTTPTransportTests.swift:78-111`). The request encoder really emits `IOData`, including the ordered zero-length end write when a promise is supplied, so the repaired outbound assertion and failure fixture align with the pinned upstream contract.

### M1: title truncation metadata — addressed in source

`WebSource.swift:12,76`, `WebTextExtractor.swift:140`, `WebSourceReader.swift:82-85`, and `WebSourceContext.swift:6,78,95-102` carry title truncation independently through extraction, snapshot, context and citation metadata. The fixture at `Tests/WebSourceRepairTests.swift:56-65` checks the 240-byte Unicode title boundary and context/citation flag. This is a new, unintegrated type, so this review found no existing persisted-schema migration affected by adding the field.

### M2: header/wire diagnostic — addressed in source

`PinnedWebTransport.swift:135-137` now uses `responseLimitExceeded`; `WebSource.swift:47` describes HTTP header/wire limits rather than claiming a 256 KiB body overflow. The body accumulator still uses its separate body-size error. Tests cover both initial-header and total-wire failures.

## DNS ownership and race analysis

The following paths were traced in source; none was executed natively here.

- **Cancellation before continuation installation:** `finish` records the terminal outcome. `resolve` observes it under the same lock and resumes the newly supplied continuation directly without starting DNS. A queued cleanup with no handle/lease is harmless.
- **Completion during deadline installation:** the second locked check detects an already completed outcome and cancels the newly returned deadline token. No service work is admitted from that branch.
- **Cancellation between admission and queue startup:** the queued setup closure captures both operation and lease, installs the lease on the service queue, sees the terminal outcome and releases capacity without calling the DNS API. An earlier no-op cleanup cannot lose the later lease.
- **Cancellation/deadline during blocked setup:** caller completion does not depend on the service queue. The executing setup closure retains the operation and lease. When setup returns, it installs the returned handle and immediately cleans it if the caller already finished. Capacity remains consumed until that cleanup returns.
- **Callback success/failure racing cancellation:** the outcome lock selects one terminal result. Callback processing itself is serialized and checks terminal state before accumulating addresses. A cancellation after a successful result is additionally checked before the resolver returns to the transport. There is no path from a timed-out/cancelled resolver into a later socket connect in the inspected caller flow.
- **Late callback/deadline:** repeated `finish` calls do not resume the continuation again or schedule repeated terminal cleanup. Receivers ignore records after completion. Weak callback/deadline captures avoid a persistent cycle through the callback box or timer.
- **Exactly-once cleanup:** `cleanup` takes and clears the handle before `cancel`; later cleanup calls see nil. The lease has its own idempotent release and is cleared after release. No lock is held while calling DNS APIs, cancellation, continuation resume or deadline cancellation, avoiding an obvious lock/reentry cycle.
- **System API ownership:** `SystemWebDNSAPI.start` retains its callback box before calling C, releases it on setup failure, and transfers it to `Handle` on success. Dispatch-queue installation failure cancels that handle on the same queue. Successful-handle cancellation deallocates the DNSServiceRef before releasing the box. All handle/API operations stay on the service queue; no cross-thread deallocation was introduced.
- **Admission scope:** production defaults share one two-slot pool. Successful callers can briefly overlap their subsequent connection with queued DNS cleanup, but the DNS slot is still held until cleanup completes. The pool limits DNS work, not the entire application's independently constructed readers; future integration must still retain the intended single-reader/session ownership.

I found no static leak, use-after-free, double-release or premature capacity-release path in these cases. This is not a substitute for verifying ARC lifetimes, DNSServiceRef callback cancellation behavior and Swift 6 concurrency on the target platform.

## Security boundaries preserved

`WebURLPolicy.swift`, `WebResponsePolicy.swift`, dependency versions/revisions, certificate fixture and notices are unchanged by hash. Literal IPv4 parsing and connection, original-host TLS verification/SNI/Host, TLS minimum, required peer authentication, disabled tickets/resumption/renegotiation, and per-evaluation trust-fetch restriction are unchanged in executable code. The TLS edits narrow the documentation claim rather than weaken trust.

The repair does not add redirect following, hostname reconnect, IPv6/private-network fallback, cookies, client credentials, browser sessions, JavaScript, subresources, model actions, remote summaries, persistence or automatic retries. Retained DNS work after caller cancellation is acknowledged and bounded; it is not allowed to lead to a source connection after that caller fails.

## Remaining native acceptance gates

All original declined-to-judge categories in `REVIEW_INPUT.md` remain open. In particular:

1. **Resolve and compile:** native SwiftPM resolution must reproduce the exact pins; strict Swift 6 compilation must pass for the production code and all 37 authored tests. Retain full diagnostics/result bundles. A passed Python/C check is not a substitute.
2. **Execute and extend DNS lifecycle tests:** run the blocked-setup, timeout/cancellation, late-callback, cleanup and admission tests. Also cover completion before/while continuation or timer installation, setup throwing, callback success versus cancellation concurrently, cleanup itself blocked, and exhaustion of both production slots. Check resource counts, deallocation and eventual slot reuse under sanitizer/stress runs. The current four DNS methods cover useful controlled interleavings, not all these schedules.
3. **Keep tests bounded:** several DNS tests use manually fired deadlines and then await task values. Run them under a finite test-runner timeout, and make failure paths cancel/unblock fixtures, so a broken callback cannot stall the entire native gate indefinitely. This is a test-runner obligation, not evidence of a production deadlock.
4. **Native DNS/socket routing:** controlled mixed/private/excessive/rotating answers must show that only the selected validated public literal reaches the socket and the hostname is never re-resolved for connection. Verify no late socket operation after cancellation or timeout.
5. **TLS and network privacy:** on iOS 26 verify correct original-host system trust, wrong-host/expired/untrusted/missing-chain and old-TLS rejection, no client identity/session reuse, and no per-reader AIA/OCSP request to an unvalidated destination. Distinguish OS trust-database maintenance from per-evaluation fetches.
6. **Transport/parser behavior:** execute the production NIO fixtures for framing, informational responses, limits, trailers, compression rejection, errors, cancellations and shutdown. Capture success/failure evidence for real approved public retrieval rather than treating the previous DNS-failed probe as success.
7. **Context/extraction:** run the added actual Swift `JSONEncoder`, Unicode/escaping, inline adjacency and truncation tests; measure worst-case CPU/allocation behavior and cancellation latency. No local-model synthesis or prompt-injection guarantee follows from these data-preparation tests.
8. **Disposable application integration:** verify explicit URL consent, local-only provider selection, complete model-context budgeting, citation lookup, per-source errors, stale-result suppression, offline behavior, IPv6-only limitations, full app regressions and installed/memory/energy footprint. Do not enable the active candidate before these gates pass.

## Final disposition

I1-I4 and M1-M2: **source-level closure accepted for this exact repaired manifest**. No further repair is demanded by this scoped static re-review before starting native validation. Native/runtime safety, real retrieval and release readiness remain **unverified and blocked on the stated acceptance gates**.
