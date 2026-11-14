# Recoverable model installation

Source inspection found that LocalModelStore replaced model bytes before setting protection and writing its manifest. A later failure could leave changed bytes despite a failed installation. New synchronous ModelInstallTransaction stages model+manifest and applies protection before publication, copies both previous files, publishes a bounded prepared journal, then atomically renames each staged file. Removing the prepared marker is the commit point. Failed operations restore both files, including previously absent files. Recovery copies rather than consumes backups and retains the journal after partial failure. Startup and store path/manifest access retry recovery before exposing model state. Actor-isolated synchronous execution prevents reads interleaving with its two renames. Extra staging and backup disk space is checked before commit.

Nine exact production-helper tests execute actual temporary filesystem operations: success, injected failures after either publication, absent previous files, preparation failure, interrupted restart recovery/idempotence, missing backup rejection, partial rollback failure/retry, orphan staging cleanup, and traversal/symlink rejection. 213 total selected Swift6.1.3Linux tests pass;132Python tests pass;186Swift files syntax-parse. The initial test-first proof failed to compile because the new helper interface did not exist; do not describe that as an executed regression of old code. The prior defect was established by source inspection, not native runtime reproduction.

Native LocalModelStore reopen+verifiedURL integration test is added to the Apple gate but unexecuted here. CryptoKit, file-protection attributes, iOS storage behavior and inference require Apple validation. This is recoverable process-interruption ordering, not guaranteed power-loss/media-failure durability (no file/directory fsync guarantee). The two renames are not globally atomic; the owning store prevents reads until completion/recovery. External filesystem mutation is unsupported and invalid recovery blocks access rather than discarding backups.

Independent review found no concrete install/rollback loss flaw. It separately identified existing remove(_:) deleting bytes before manifest save; that deletion path is not fixed by this installation change. No IPA/catalog publication.

## Deletion follow-up

The separate deletion-before-manifest weakness above is now repaired in source. LocalModelStore.remove encodes filtered metadata before invoking the same synchronous transaction with no new model source. Old model/manifest backups and protected staged metadata precede unlink; the prepared journal restores old bytes and metadata after failure or restart. Existing missing-model deletion remains allowed so stale metadata can be cleared.

Six new actual filesystem tests cover successful deletion, injected failure after either publication, absent-model success/failure, preparation failure, and restart after deletion. Total15transaction tests and219selectedSwift tests pass in proof-26-deletion-boundaries.132Python tests pass;186Swift files syntax-parse. Independent review found no new flaw. Initial test-first missing-interface compilation failure is not claimed as executed old-code regression.

The shared helper copies backup data before deletion; insufficient space can prevent deletion safely, leaving original files unchanged. No low-disk success guarantee. The existing Apple LocalModelStore deletion test remains required and unexecuted here. No power-loss guarantee or release claim.

## Space-efficient deletion recovery

Deletion backup and recovery staging now try a same-filesystem hard link first, then fall back to a complete copy when linking is unavailable. Installation still copies its previous model as before. No linked inode is changed in place; replacement is by rename and cleanup only removes links. This avoids duplicating up to2GB merely to delete a model on supporting filesystems. Metadata writes and fallback copies still require free space; this is not a universal low-disk guarantee. Native APFS/file-protection behavior remains unverified.

Actual inode/content regression failed before optimization and passes after.16filesystemtransaction tests and220selectedSwift tests pass in proof-28-deletion-link-green;132Python pass;186Swiftfiles syntax-parse. Independent review found no concrete flaw; repeated same-inode rename during recovery may leave a scratch link, safely removed by transaction cleanup. The single-owner/no-in-place-write invariant must remain.
