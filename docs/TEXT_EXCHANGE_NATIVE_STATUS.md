# Native text exchange integration

The one-shot exchange adapter and native harness were integrated byte-for-byte from **699764b706633b2a7268bc41241587de11215219**, verified by [run 43666696490](https://github.com/R347H4CK3R/Orivyn/actions/runs/43666696490). Downloaded artifacts confirm **8/8 end-to-end exchanges**, **8/8 authentication checks**, and **7/7 channel checks**. Swift source hashes were compared before integration.

The success case uses actual Network.framework mutual TLS and two SQLite databases. Rejected scope, stale epoch, revoked receiver, forged payload digest and forged receipt identity cannot commit or acknowledge unauthorized data. Lost-receipt recovery first commits one receiver import, closes the connection before acknowledgement, confirms sender state remains pending, then retries and confirms exactly one imported conversation plus successful delivery.

All eight cases, including lost-receipt recovery, are retained in docs/evidence/peer-auth/text-exchange-retry-20261115.json with exact source manifest. The rejected-packet cases are not a comprehensive security proof. Revocation timing races, foreground lifecycle and physical-network/device behavior remain untested.

**The app still does not enable ORIVYN_PEER_TLS_SPIKE.** This integration does not activate network access, create identities or start scheduling. The application still needs trusted pairing/identity provisioning, consent lifecycle, unsaved-edit coordination, automatic scheduling and device acceptance before it can claim live automatic sync.

Main application implementation 8ab97c4 separately passed 1,024 native tests with 5 skipped and zero failures; that result does not certify this later integrated head. Its ui-1 shard passed 17 tests, including the previously intermittent new-conversation case. The lazy-form agent-create test now passes, but the Photos cancellation to Files picker test failed. The isolated three-repeat new-conversation diagnostic remains in progress.

Vision alternative ef6989c completed all frozen cases but matched 4/10; it is rejected. General unreviewed autonomy remains incomplete. The completion diagnostic required binary, argument and output-capture corrections; empty outputs are invalid observations, not improvements.

Build 8 remains an unpublished draft, with no SideStore feed changes.
