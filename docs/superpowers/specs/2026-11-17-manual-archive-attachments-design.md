# Explicit retained-file association (incremental, not automatic restoration)

## Scope and authorization
The owner requested continued safe attachment restoration. The approved incremental path lets the owner choose one exact retained file and one already imported, visible message, then review and confirm that pair. It does not infer relationships from filenames, content references or unverified export formats.

Legacy `assetsJson` parser integration is preserved on the separate local `fix/legacy-archive-attachments` branch at `6b582de`. No positive original-template compatibility fixture was found. That parser is excluded from this candidate application, not advertised as supported.

## Flow
1. Read a preserved, hash-bound preparation and paginate eligible files (50/page, supported importer types, at most10MiB).
2. Owner selects a file. Independently list/search supported visible imported messages,50/page. Never preselect or suggest a target.
3. Owner selects a message. Refresh exact prepared evidence and actual current persisted message. Require unchanged core, erasure epoch, and an all-new text restore receipt. Old mixed preserved/imported receipts cannot establish membership and fail visibly.
4. Show the exact filename/path, size, target conversation/message and current text. Cancel is read-only. Confirm authorizes only this pair.
5. Hold history/cleanup serialization, revalidate archive/evidence, copy through no-follow descriptors, run the existing type-validating importer, reverify original bytes/hash, and append the attachment in an independent SQLite transaction.

## Invariants
- Source has explicit `userReviewed` origin. The inventory SHA is its evidence hash, not a claimed exporter mapping.
- Receipt uniqueness spans archive/message/path across origins and evidence hashes. Changing origin or map evidence cannot duplicate or resurrect an attachment. Full immutable source still must match.
- Original ZIP, unsupported files, text-restore receipt, message core, existing attachments and unresolved-reference records remain intact.
- Do not expose hidden/system branches as targets. Imported file text remains untrusted attachment material, never tool authorization.
- Successful staging ownership is transferred before observing cancellation. The caller installs cleanup immediately; no output URL is lost by a post-worker cancellation check.
- Precommit cleanup touches only freshly owned files. Durable commit prevents cleanup even if refreshing the visible catalog fails; history editing/GC stay locked until recovery.
- No network fetch or upload. Later explicitly selected remote-model use can send attachment excerpts, disclosed in review.

## Required proof before release
Portable service/persistence/ownership tests; adversarial selection/hash/path/epoch/replay tests; independent review; exact Apple native importer tests plus explicit UI selection/cancel/confirm/relaunch/actual QuickLook preview and no duplicate replay. Bump version/build and in-app/catalog notes only for a verified release. Private archive and physical-device acceptance remain unverified.
