# Focused web-reader repair revision

Scope: four Important findings (I1–I4) and two minor findings (M1–M2) in REVIEW_INPUT.md. Work exists only in /workspace/shared/Jarvis-EVO-web-repair-work. The original /workspace/shared/Jarvis-EVO-web-work is unchanged, including its original 40-entry manifest and hash 491958ea5d810daa3a66787b2f2b04594ca7a8ac2a376bb5eb943c4f322ffba7. No copy-back, app integration, push, CI change or publishing occurred.

## Authored repairs

- I1: WebSourceContext first reserves metadata, then up to 256 UTF-8 bytes of meaningful text per source. It distributes spare JSON-encoded byte budget across remaining text, gives unused short-source allowances to others, and binary-searches valid-scalar prefixes against actual JSONEncoder escaping cost. If metadata plus all minimum excerpts cannot fit, it throws contextTooSmall instead of retaining empty evidence entries. Truncation flags remain explicit.
- I2: DNS caller outcome/continuation and deadline are lock protected and independent of the service queue. A five-second caller deadline is scheduled before setup. Cancellation or expiry can resume the caller while DNSServiceGetAddrInfo is still blocked. API start, callbacks and DNSServiceRefDeallocate remain on the same private serial queue; the operation is retained until late setup returns and its handle is cleaned. A shared two-slot admission pool counts both active operations and abandoned blocked setup/cleanup, releasing capacity only after cleanup returns. Excess calls fail busy rather than enqueue more blocking OS work. This does not force-stop OS IPC or promise hard real-time scheduling.
- I3: Ordinary inline elements no longer insert spaces into adjacent numbers/words. Separators are restricted to block/break boundaries and deliberately removed content. The bounded non-rendering tokenizer remains in place.
- I4: WebReadOperation applies one error policy at its exactly-once completion boundary for bootstrap, request writes, inbound parsing and body failures. Cancellation and classified source errors are preserved; HTTP parser errors become invalidResponse, timeouts remain timeout, and raw connection/route failures become transportUnavailable. A failed route is not labeled as device-wide offline. Known offline remains the reader's explicit reachability check. No detailed platform errors or source paths are logged.
- M1: titleTruncated propagates from extraction into the retrieved source, model-context entry and citation metadata. Body/context truncation remain separate.
- M2: initial-header and total-wire limits use responseLimitExceeded instead of the misleading 256 KiB body message.

Additional test-fixture correction discovered while inspecting upstream contracts: HTTPRequestEncoder emits IOData, so the outbound request assertion and injected write-failure handler now use IOData rather than ByteBuffer. No transport or dependency change accompanies this correction.

## Invariants preserved

PublicWebIPv4 and UserSuppliedWebURL policy, validated literal socket destination, original-host TLS/SNI/Host binding, minimum TLS version, platform trust evaluation, lack of production custom anchors/trust bypass, and disabled TLS tickets/resumption remain unchanged. Dependency versions, revisions and license files are unchanged. Certificate network fetching is disabled for the particular trust evaluation, not globally for Security.framework; documentation now explicitly disclaims absolute OS network silence and retains native AIA/OCSP instrumentation gates.

## Native regression sources

There are now 37 authored XCTest methods in seven files (13 additional methods). New tests cover three equal long sources, unequal/escaped/Unicode source text, long metadata with insufficient useful excerpt budget, exact inline numbers/words, title truncation, pre/post-activation and write/body error paths, header/wire diagnostics and consistent single/batch failures without partial sources.

WebDNSLifecycleTests injects an API setup gate and manually triggered deadline scheduler. It tests a blocked setup with timeout; immediate caller cancellation while setup remains blocked; late setup success after caller completion; late deadline/callback delivery; exact-once service cleanup; admission remaining occupied until abandoned setup is cleaned; subsequent slot reuse; private answers; and excessive record counts. The fixtures do not alter production DNS/TLS policy or make actual network requests. Service-queue draining avoids a test-only race between the cleanup expectation and admission-slot release.

## Verification performed and remaining

- Original frozen manifest entries and manifest hash were checked before copying and are rechecked at freeze. Exact before files are retained under before/; complete repaired deliverables are under after/. FOCUSED.patch contains the authored source/test/document changes. BEFORE_SHA256.json and AFTER_SHA256.json record the comparison inputs.
- The six existing independent Python/C reference checks were rerun in the repair copy and pass, including the 18 upstream C framing split cases and 12 malformed-frame cases. They do not execute the changed Swift code, DNS lifecycle, JSONEncoder allocation or native error handling.
- A small independent Python JSON calculation verified that the long-URL fixture's 12,500-byte budget is above its estimated 12,228-byte metadata but below the 12,996-byte metadata-plus-minimum allowance. This is a fixture sanity check, not a Swift execution result.
- Native RED and final test commands both failed to start because swift is not installed. No Swift compile, SwiftPM resolve, XCTest, simulator/device execution, verified RED/GREEN or repaired runtime guarantee is claimed. Native logs are retained.
- No real public-page probe was retried. The original attempt stopped at DNS resolution, before connecting. Successful native or independent real retrieval remains unverified.
- Targeted independent re-review is still required, especially DNS ownership, cancellation races, deferred cleanup and bounded admission. Then all native acceptance gates and full app gates remain mandatory. No user-facing entry point is enabled.

## Reviewer focus

Read WebDNSResolver.swift as two ownership domains: lock-owned outcome/continuation/deadline versus serial-queue-owned setup handle/records/lease. Cancellation never directly deallocates a reference in use by setup. Check setup-before/after-completion races, callback/cancel races, exact-once cleanup, and capacity release after blocking cleanup. Review context accounting with JSON escapes and tiny metadata-adjacent budgets, then inline boundary semantics and terminal error classification. Any claimed success beyond the executed independent checks must await native evidence.
