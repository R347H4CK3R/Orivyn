# Plugin credential preservation on removal failure

A production `PluginBroker.removeConnection` failure was reproduced: it removed the credential before writing connection metadata, and a metadata-write error left the saved connection without its credential. The host regression runs the exact broker and journal with real Foundation file writes; only Keychain and network are explicit synthetic boundaries. No real credentials or server are used.

The synchronous compensating helper reads the previous credential before deletion. If metadata saving fails, it restores that credential and rethrows the original failure. If restoration also fails, it emits a token-free recovery-required error. In-memory connections change only after successful completion. Active sessions are still disconnected intentionally before removal and are not silently reconnected on failure.

This is not crash-atomic across Keychain and a file, nor proof of physical-device Keychain behavior. Existing atomic metadata writes must retain old metadata when throwing. No token enters logs, metadata or evidence. The actual host regression checks both failure preservation and successful persisted removal. Six separate Foundation helper tests cover success/read/delete/metadata/rollback failures and no-credential handling.

Evidence preserves an initial host disk-full setup failure, then the actual pre-fix lost-credential failure (`plugin-removal-broker-red-2`) and passing post-fix run (`plugin-removal-broker-green`). Static Linux Foundation linking reports its upstream mktemp warning; this is not an iOS build. Superseded rebuildable binaries/caches were removed with recorded hashes/paths to recover disk; sources, manifests, commands and logs remain.

Final verification:304 Foundation XCTest,135 Python tests,74 agent Node tests and39 VM Node tests pass. Actual production broker host smoke passes two scenarios with the stated boundaries. Independent review found no concrete integration defect. Private checkpoint6e7aa13c49019fdcfd8a1ba681da1603affcf331 exact broker source fetched and matched. No release/IPA/catalog changes.
