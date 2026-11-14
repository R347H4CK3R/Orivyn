# Data integrity and transfer status

Automatic multi-device synchronization is **not implemented or verified**. Current transfer is an explicitly selected version-1 JSON backup. It includes chat text, extracted attachment text, and memories, not original attachment files or full workspace state.

This pass fixes three source-reviewed integrity issues:
- Memory replacement now updates its SQL creation-date index together with its JSON payload. The old source upsert was executed against real Python SQLite and reproduced incorrect ordering; the production SQL now passes the same regression.
- String binding supplies its explicit UTF-8 byte length, preserving searchable text after embedded NULs rather than truncating it while leaving the JSON payload intact. Native roundtrip/search regression authored, not run.
- Delete-all treats transaction commit separately from later checkpoint/compaction. A cleanup error returns a warning after deletion succeeds; AppModel clears deleted rows and reports maintenance separately. This does not certify physical secure erasure.

Import policy is unchanged: matching identifiers replace entire records, including when the backup is older. The previous vague “merge” wording is replaced by an explicit overwrite warning and confirmation before choosing a backup. Users are advised to export current data first. Conflict-copy recovery and automatic sync remain missing; no claim otherwise. Image identity checks, whole-import validation and rollback remain unchanged.

Added two native persistence regressions and PersistenceTests to the manual native gate. Native code/UI tests remain uncompiled/unrun. Four portable integrity checks pass (one executes actual production SQL; the others are source-contract checks). Full local suites: 110 Python, 60 agent JavaScript, 39 VM JavaScript passed; shell syntax and diff checks clean. No paid CI, account connection, cloud transfer, source publication, IPA, version, or catalog change.

Follow-up: Settings/AppModel now default to an additional preserve-local/add-missing-only mode. Explicit replacement remains available. See CROSS_DEVICE_TRANSFER_STATUS.md for the current transfer behavior and signing blockers.
