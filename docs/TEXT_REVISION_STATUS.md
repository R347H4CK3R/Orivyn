# Text revision receiver status

The dormant receiver accepts canonical text revisions only after its caller authenticates a peer and approves the exact bytes. Matching remote ancestry advances an unedited mapped row; committed local edits are preserved in a separate conflict copy. First contact cannot adopt an existing local row, even when identical. Transactions bind receipts, ancestry and content; capacity failures roll back. Revocation and history erasure invalidate corresponding state.

All 129 production persistence tests passed on a48a59c3 in https://github.com/R347H4CK3R/Orivyn/actions/runs/43653606975 . This includes 13 receiver lineage checks and 17 durable sender checks. They execute production Swift and SQLite on Linux, including delivery simulated between two stores, not two networked devices. See TEXT_REVISION_SENDER_STATUS.md for sender guarantees and limits.

Automatic sync remains incomplete: authenticated pairing, active transport, live lifecycle leases, automatic selection and approval policy, bidirectional convergence, unsaved UI edit coordination, attachments, and two-device acceptance remain unfinished or unverified. History erasure requires fresh explicit authorization; silently refreshing epochs must not restore erased history. No live receive path is enabled.
