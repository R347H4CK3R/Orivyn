# Combined foreground sync candidate

This isolated candidate combines app/session/recovery source da73493, idle/busy scheduler source a3b81015, real identity source1032b209 and verified dependency graph/build scripts91a474c. History-import page remains f00d914; Files cancellation regression is independently tracked. Normal shipping SPI stays off.

The prior candidate7231e0 failed device compilation due to Swift6.2.4 IR generation crash in PeerSyncSettingsView.swift, Boolean isolation reabstraction thunk. The candidate removes custom Bool bindings without bypassing isolation or authorization. New gate performs actual device and simulator compile, 19 history/session tests including real Keychain pairing/revocation state, and 31 native auth/channel/exchange/controller cases. All results are pending for this combined source.

Previous independent evidence: 17 portable scheduler checks, 10 portable pairing policy tests, 28 native peer checks at479d, and lean/peer project generation plus stock-runtime device app/test compilation at91a474c passed. They do not substitute for this integrated gate.

Limits: physical devices, positive complete paired-app transfer, receiver busy after authenticated connection, and real UI interaction remain unverified or unfinished. Cross-peer busy currently fails closed rather than acknowledging delivery. No release publication from this branch.
