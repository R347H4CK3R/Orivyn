# Native peer authentication status

The hardened PeerTLSProbe passed all 8/8 actual macOS mutual-TLS loopback checks at 03c88b944ebb1f8984f59a71ae884d77fd87ba93 in https://github.com/R347H4CK3R/Orivyn/actions/runs/43655527605 . Its source, harness, pinned dependency build and regression workflow are integrated at b9ce34fa. Integrated source/harness hashes match the tested artifacts. See evidence/peer-auth/hardened.json.

The valid pair authenticated on both sides. Unpaired clients, mismatched pairing generations, expired/future certificates, wrong TLS usage, unknown critical extensions and invalid self-signatures were rejected without timeout. Tests used Apple Network/Security, disposable P-256 identities imported into process memory, and random challenge/echo frames. They involved no user history, production keys or synchronization payloads.

The checker uses pinned Apple swift-certificates for independent signature and profile validation, followed by platform TLS policy evaluation. The build records exact upstream revisions. Missing validation modules fail closed. The app does not yet link these dependencies or enable ORIVYN_PEER_TLS_SPIKE: no listener or automatic sync has been activated.

## Preserved baseline failure

Baseline run https://github.com/R347H4CK3R/Orivyn/actions/runs/43654707674 at 42ebe15d passed six of eight cases. Platform trust accepted an unknown critical extension and invalid self-signature when the exact leaf was used as a trust anchor. Both failures remain in evidence/peer-auth/baseline.json; they were not reclassified or skipped.

## Same-connection bounded channel

Candidate 960d99b981aeb1c6d5933e323e75537744c0d9aa passed Apple SDK type-checking, all eight authentication regressions and seven real Network.framework channel checks in https://github.com/R347H4CK3R/Orivyn/actions/runs/43661550507 . The integrated implementation and harness hashes match the verified artifact. See evidence/peer-auth/channel-auth.json, channel-results.json and channel-source-sha256.txt.

The transfer API retains the exact authenticated TLS connection and binds local/peer certificate hashes and pairing generation. The original probe API still closes after authentication and its Result is not transfer authority. A channel permits one bounded message per direction, with a 5,001,024-byte maximum, 64 KiB chunks and a 30-second lifetime. It fails closed on invalid framing, EOF, cancellation or network errors; pending callbacks are settled once.

Actual loopback checks verified a request and SHA-256 receipt, a 262,177-byte fragmented payload, the maximum payload, empty/oversize rejection, explicit channel cancellation and unpaired-peer rejection. All passed without timeouts or duplicate callbacks. Fixtures contain synthetic bytes only; no production keys or user history were sent.

## Remaining integration

This is desktop loopback transport evidence, not iOS simulator or physical-device synchronization acceptance. The app still does not enable the spike or link its X509 dependencies. The caller must cancel on revocation, lock/background transitions and consent changes; those app lifecycle connections are not implemented. The transport does not authorize database writes or establish receiver epochs, approved data scope, canonical payload validity or durable receipts.

Remaining work includes raw malicious-frame and deadline/race coverage, native certificate provisioning and keychain persistence, QR enrollment, a permission-controlled live coordinator connected to sender/receiver storage, automatic scheduling, bidirectional convergence, unsaved UI edits, attachments and two-device acceptance.

API reference: https://github.com/apple/swift-certificates/blob/8789d7e78f996d56272836c8bf3590c5bd9c9754/Sources/X509/CertificatePublicKey.swift
