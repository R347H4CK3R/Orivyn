# Text revision receiver status

Adds a dormant, receiver-only exact-base revision boundary. A caller must authenticate the peer and approve the exact bytes. Matching ancestry advances an unedited mapped row; committed local edits are preserved as conflicts. First contact cannot adopt an existing local row, even when identical. Transactions bind receipts, ancestry and content; capacity failures roll back. Revocation and history erasure invalidate the corresponding state.

Thirteen regression tests cover ancestry, duplicate delivery, canonical bytes, local conflicts, deleted targets, rollback, revocation, erasure, migration and capacity. Verification is pending CI on this commit.

This is not automatic sync completion. Pairing, authenticated transport, sender revision tracking, unsaved UI edit coordination, attachments, and two-device acceptance remain unimplemented or unverified. No live receive path is enabled by this change.
