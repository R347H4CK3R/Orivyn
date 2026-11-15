# Peer history ownership integration

This development change integrates AppModel receive ownership from aea65bd0a50fa1b4b7f7c04ccf03e3104003b3a2. It invalidates attachment cleanup before preflight, requires exact persisted/in-memory equality, rejects unsaved local history, reloads after transfer success or failure, and retains mutation ownership until recovery if reload fails. Preflight rejection remains retryable.

Native run 43676280787, job 132697035831, artifact 14145719247 executed all eight PeerHistoryAppModelTests with zero failures. Cases cover actual post-commit cancellation, SQLite-triggered unsaved turn, stale-history retry, real attachment-file retention, and failed recovery. Guarded app compilation run 43676333607 at 698dcf0e57ab866081c81256d233f218a1aefd95 passed for the same AppModel bytes, artifact 14146960046. Independent final review found no Critical or Important defect.

The wrapper remains compile-guarded; no listener, pairing, provisioning or scheduler is enabled by this change. Cancellation during preflight, suspended reconciliation, competing recovery, physical devices and actual peer-channel execution through the wrapper remain unverified.

Also integrated the Photos remote Cancel control synchronization test from 094b1979ce14452747d4854a11597fe252b0ffb2, validated by three independent targeted repetitions in run 43673325415. This is a test synchronization improvement, not a claim that all intermittent Files presentation failures are fixed. Main run 43673278573 UI-0 failed history-import Files presentation. Its later 16-test passing summary covers remaining tests after a runner restart, not a retry of the failed history-import case; the original failure remains open.

Build number advances to 9 for an unsigned development candidate. Published build 8 does not contain these changes. Integration checks and subsequent packaging must pass before updating catalogs. General autonomy, reliable broad vision, automatic sync and physical-device acceptance remain unfinished.
