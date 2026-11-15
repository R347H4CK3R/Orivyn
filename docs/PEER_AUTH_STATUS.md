# Native peer authentication status

The hardened PeerTLSProbe passed all 8/8 actual macOS mutual-TLS loopback checks at 03c88b944ebb1f8984f59a71ae884d77fd87ba93 in https://github.com/R347H4CK3R/Orivyn/actions/runs/43655527605 . Its source, harness, pinned dependency build and regression workflow are integrated at b9ce34fa. Integrated source/harness hashes match the tested artifacts. See evidence/peer-auth/hardened.json.

The valid pair authenticated on both sides. Unpaired clients, mismatched pairing generations, expired/future certificates, wrong TLS usage, unknown critical extensions and invalid self-signatures were rejected without timeout. Tests used Apple Network/Security, disposable P-256 identities imported into process memory, and random challenge/echo frames. They involved no user history, production keys or synchronization payloads.

The checker uses pinned Apple swift-certificates for independent signature and profile validation, followed by platform TLS policy evaluation. The build records exact upstream revisions. Missing validation modules fail closed. The app does not yet link these dependencies or enable ORIVYN_PEER_TLS_SPIKE: no listener or automatic sync has been activated.

## Preserved baseline failure

Baseline run https://github.com/R347H4CK3R/Orivyn/actions/runs/43654707674 at 42ebe15d passed six of eight cases. Platform trust accepted an unknown critical extension and invalid self-signature when the exact leaf was used as a trust anchor. Both failures remain in evidence/peer-auth/baseline.json; they were not reclassified or skipped.

## Remaining integration

This is desktop loopback authentication evidence, not iOS simulator, physical-device pairing, keychain persistence, live revocation/cancellation, QR enrollment, transfer framing, payload delivery or automatic synchronization acceptance. Native certificate provisioning, a permission-controlled live coordinator, bidirectional convergence and two-device acceptance remain unfinished.

API reference: https://github.com/apple/swift-certificates/blob/8789d7e78f996d56272836c8bf3590c5bd9c9754/Sources/X509/CertificatePublicKey.swift
