# Native peer authentication status

The disabled PeerTLSProbe was compiled and exercised on a real GitHub macOS 15 Intel runner using Apple Network/Security and disposable P-256 identities imported into process memory. Tests exchange only random challenge/echo control frames on loopback. No user history, production keys or synchronization traffic is involved.

Baseline run: https://github.com/R347H4CK3R/Orivyn/actions/runs/43654707674 at 42ebe15d. Six of eight cases passed. A valid pair authenticated; an unpaired client, mismatched generation, expired certificate, future certificate and wrong TLS usage were rejected. The platform accepted both an unknown critical extension and an invalid self-signature when the exact certificate was used as a trust anchor. Those two failures remain recorded in docs/evidence/peer-auth/baseline.json.

The fix is staged on codex/native-peer-auth-tests-20261114 at 03c88b94. It requires independent signature/profile validation with Apple's swift-certificates library, plus the existing platform TLS evaluation. It rejects unknown critical extensions, invalid self-signatures, incorrect lifetime/usage and CA certificates. Without the validation modules, authentication fails closed. The dedicated test checks out exact upstream revisions recorded in its source and artifact; no library dependency or listener has been enabled in the application target.

The hardened native test is queued in https://github.com/R347H4CK3R/Orivyn/actions/runs/43655527605 . Do not claim the fix passed until that run completes. The app's ORIVYN_PEER_TLS_SPIKE flag remains disabled.

This is macOS loopback evidence, not iOS simulator, physical-device pairing, persistence integration, live revocation, cancellation, QR enrollment, transport framing, or automatic synchronization acceptance. Native certificate provisioning and a permission-controlled live coordinator remain unfinished.

API reference: https://github.com/apple/swift-certificates/blob/8789d7e78f996d56272836c8bf3590c5bd9c9754/Sources/X509/CertificatePublicKey.swift


## Hardened native result

Commit 03c88b944ebb1f8984f59a71ae884d77fd87ba93 passed all eight actual macOS mutual-TLS checks in https://github.com/R347H4CK3R/Orivyn/actions/runs/43655527605 . The valid pair authenticated on both sides; seven invalid cases were rejected without timeout, including unknown critical extensions and a bad self-signature. See evidence/peer-auth/hardened.json. The tested source, harness and pinned dependency build are now integrated into the development branch, with a dedicated native regression workflow.

The checker uses pinned Apple swift-certificates to validate certificate profile and signature before platform TLS policy evaluation. If those modules are unavailable, it fails closed. The app does not yet link these dependencies or enable ORIVYN_PEER_TLS_SPIKE; no listener or automatic sync has been activated. This is desktop loopback authentication evidence, not iOS, physical-device, keychain persistence, live payload delivery, revocation-lifecycle or two-device acceptance.
