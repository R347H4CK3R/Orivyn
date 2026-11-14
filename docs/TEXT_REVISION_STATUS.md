# Text revision receiver status

The dormant receiver accepts canonical text revisions only after its caller authenticates a peer and approves the exact bytes. Matching remote ancestry advances an unedited mapped row; committed local edits are preserved in a separate conflict copy. First contact cannot adopt an existing local row, even when identical. Transactions bind receipts, ancestry and content; capacity failures roll back. Revocation and history erasure invalidate corresponding state.

All 112 production persistence tests, including 13 new ancestry, conflict, duplicate, canonical-byte, deleted-target, rollback, revocation, erasure, migration and capacity tests, passed on commit 439d7850be1a0bfb8dbc7763cee448133aa77e32 in https://github.com/R347H4CK3R/Orivyn/actions/runs/43651748011 . Subsequent portable checks also passed on 14739e7d and a6a8240d. These are Linux Swift 6.1.3 tests, not iOS or device acceptance.

Automatic sync is not complete: authenticated pairing, active transport, sender revision tracking, unsaved UI edit coordination, attachments and two-device acceptance remain unfinished or unverified. No live receive path is enabled by this change.
