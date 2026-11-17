# Reviewed legacy archive attachment supplements

Goal: restore an actual supported local attachment to an already imported visible message, without replaying or changing the original text-restore receipt. Root approved this narrow legacy scope on 2026-11-17. Build21 remains published unchanged while this branch is developed.

## Evidence and limits
Independent public converters observe legacy chat.html `assetsJson` as message.id to exact relative paths. This is not an official stable schema, current index.html support, individual opaque-reference resolution, or evidence about the user's private archive. Only UUID message IDs uniquely present in supported visible plan messages are eligible. Unknown/ambiguous cases remain retained. No basename, display-name, suffix, URL, percent-decoding or pointer-prefix guesses. Never execute HTML/JavaScript. Keep unresolved records/counts unchanged.

## Alternatives
1. Guess reference IDs from export filenames: rejected, unsupported identity inference.
2. Enrich original archive commit: rejected for existing imports because immutable receipts and local-edit preservation must remain intact.
3. Separate reviewed, one-file supplemental transaction: selected. It works after text restoration while binding the exact target message and source evidence, at the cost of explicit individual review and limited formats.

## Flow and ownership
Read a hash-bound retained job's unique legacy chat.html and strict static map. Join canonical UUID keys against unique visible plan messages and exact retained inventory paths. List bounded candidate metadata. User selects one file, sees target conversation/message, path, bytes and supported format; no file is attached until explicit confirmation.

On confirmation, serialize history changes; revalidate original archive, state, plan, map, inventory, current epoch and target message. An existing immutable supplemental receipt means no new copy or reattachment. Otherwise no-follow copy the exact file into an exclusive private staging name while checking expected size/hash. Only supported image/PDF/UTF8-text files at most10MiB enter the existing validated attachment importer, including image provenance/preview/OCR. Reverify imported original bytes and preserve the source ZIP. Unsupported or changed files fail without modifying history.

The SQLite transaction requires an unchanged reviewed current message snapshot and the current erasure epoch, appends only this validated attachment, and saves a unique archive/map/message/path receipt atomically. Preserve every other conversation/message field and existing attachments. Original archive receipts remain untouched. On precommit failure remove only newly owned import files. After committed receipt, never delete assets or report rollback because later reload/marker updates fail. Startup GC may collect precommit orphan files, but never files referenced by committed history. A removed attachment is not silently reattached by replay.

## Gates
Synthetic-only parser differential/adversarial tests; retained-service path/hash/identity tests; SQLite replay/edit/erasure/rollback tests; importer ownership/cancellation tests; real native UI preview after commit/relaunch, cancellation and no mutation before confirmation. Full exact-source release gate and independent review before publishing. Version bump only for a validated release; no claim of universal media or private-backup acceptance.
