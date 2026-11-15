# Disabled native mutual-TLS control probe

`PeerTLSProbe.swift` is a real Network.framework/Security implementation behind `ORIVYN_PEER_TLS_SPIKE`. No project or build configuration defines that flag. It has NOT been compiled against an Apple SDK, run in a simulator, or exercised on a device. Production has no peer listener or automatic sync. Do not enable this flag in a release based on portable test results.

The source constructs TLS 1.3-only client/listener parameters, requires a supplied local SecIdentity and remote certificate pin, requires peer authentication in both roles, disables tickets/resumption/false start, and checks the exact leaf SHA-256 and P-256 key attributes. Trust evaluation is offline, uses the proper TLS client/server policy, and anchors only to the locally paired certificate. The pairing initializer rejects a changed scanned pin and the same local/remote certificate. No certificate or private key is generated, logged, exported, or persisted by this spike. Native certificate provisioning and bilateral physical pin verification are absent.

A caller must explicitly supply a pair and invoke connect/listen. The listener accepts at most one connection; a second start fails without disturbing the first probe. One serial queue owns callbacks, cancellation, timeout, and state. The deadline is 30 seconds. The caller must retain the probe and cancel on lock, background, or revocation; no lifecycle integration is claimed. Cancellation prevents future callbacks from sending further frames, but cannot retract bytes already handed to the OS.

Only two fixed-size frame types exist: random challenge and echo. Each side generates 32 bytes using SecRandomCopyBytes, exchanges the local pairing generation, checks the other challenge differs from its own, and requires both nonces in the final echo. Success immediately closes the channel and returns a diagnostic result. This result is NOT a data-transfer capability or consent token. There is no private-content frame, arbitrary send API, persistence call, automatic reconnect, discovery, or AppModel wiring. Accordingly this probe does not complete automatic sync or provide a usable text-transfer feature.

The shared framing implementation validates its 9-byte header and exact kind-specific body length before a native body read: 68-byte challenge or 100-byte echo. Malformed versions/kinds/UUIDs, oversized declarations and truncated reads fail. The standalone decoder/accumulator rejects trailing bytes. The native transport reads exactly two frames and closes; extra bytes queued after the final echo are discarded without inspection, not proven absent. A complete final read is accepted even if EOF arrives with it; short EOF fails. Actual EOF/callback behavior remains a native test gate. Eight portable framing tests cover every split point and byte-at-a-time delivery. The full exact-source host harness passes 64 cases (8 framing, 16 receive transactions, 40 prior). `PeerTLSProbe.swift` itself is excluded from that Linux harness; these tests do not validate TLS, trust, native callback semantics or lifecycle cancellation.

## Mandatory native gates

First typecheck the gated implementation under the actual deployment SDK/Swift concurrency settings. Implement per-installation key/certificate provisioning into device-bound Keychain and bilateral pin pairing. Demonstrate wrong/missing cert, changed pin, wrong key algorithm, TLS version mismatch, timeout, canceled callback, lock/background, denied local network and two real-device handshake behavior. Explicit anchor handling MUST reject expired/not-yet-valid certificates, invalid self-signatures and unsupported critical extensions; this source currently delegates policy to SecTrust, and Apple anchor semantics must not be assumed to satisfy those checks. Until that is proven or a reviewed certificate parser adds explicit checks, keep the spike disabled. Test connection/pair revocation and no handshake resumption using packet evidence with synthetic data only.

Then implement exact immutable manifest/payload consent and durable sender/receiver session integration, using the existing atomic text-receive receipt API only after those gates. A native TLS handshake alone does not authorize any conversation bytes. Attachment file transactions, causal revisions, installation binding and two-device acceptance remain separate unfinished requirements.

API references used: [Apple Network security options](https://developer.apple.com/documentation/network/security-options), [NWConnection](https://developer.apple.com/documentation/network/nwconnection), [bounded receive](https://developer.apple.com/documentation/network/nwconnection/receive(minimumincompletelength:maximumlength:completion:)). These references establish API intent, not execution evidence.

Source review corrected a final-echo race: rejecting `isComplete` on an otherwise exact read could report failure when the successful remote closes. Native read now accepts the complete frame and rejects only insufficient data/error. Review also clarified that portable trailing-byte rejection does not establish an absence of extra bytes in native socket buffers. No native runtime test is claimed for either behavior.

### Standalone Apple SDK compile gate

The core Mac job (and local `ci_macos.sh` default `all`) runs
`bash scripts/typecheck_peer_tls.sh <evidence-directory>`. It invokes Swift 6
with complete strict concurrency against the arm64 iOS 26 simulator SDK, matching
`project.yml`. Only that compiler command defines `ORIVYN_PEER_TLS_SPIKE`;
production app flags remain unchanged. An additional compile-only source imports
Network, Security and CryptoKit and references the probe type, so an unavailable
module cannot silently turn the guarded probe into an empty successful check.
Compiler output is retained as `peer-sdk-typecheck/compiler.log`; missing SDK,
missing compiler, or compiler errors fail the core job.

This gate performs no executable launch, listener creation, connection, pairing,
or persistence action. Passing it establishes SDK/type compatibility only.
Certificate trust semantics, mutual TLS handshake, cancellation under callbacks,
and physical-device behavior remain separate unverified runtime requirements.
Portable command mocks validate orchestration, not Apple compilation.
