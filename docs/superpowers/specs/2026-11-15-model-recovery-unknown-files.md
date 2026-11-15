# Preserve unexpected model transaction data

User goal: reliable model installation/removal without losing existing data. Engineering decisions delegated; no new user-facing feature or release implied.

Reproduction: exact production ModelInstallTransaction.recover(root:) deletes unrecognized-backup inside its fixed staging directory when prepared.json is absent. Regression fails both expected-error and preserved-bytes assertions. This is a data-preservation defect, not evidence that users have encountered it.

Approaches: leave recursive deletion (unsafe for unexpected data); introduce a new owner journal format (larger compatibility migration); or validate existing staging names and restrict cleanup to regular known files and nonrecursive directory removal. Choose the last, preserving the existing journal format and normal crash rollback.

Design: validate the directory entries against the seven transaction filenames before recovery changes live destinations. Unexpected names block with existing invalid-state error. At cleanup, prevalidate every remaining entry as a regular file and refuse a present prepared marker. Delete only known entries, then rmdir the empty staging directory; never recursively delete unknown files/subdirectories. Known valid legacy partial staging remains recoverable. Existing single-owner synchronous assumption remains; this is not a guarantee against hostile concurrent same-UID mutation or media corruption.

Tests: red regression for unknown unprepared file; unknown directory/nested bytes, unexpected prepared-state entry, known-name directory/symlink, valid cleanup and all rollback tests. Run focused and full portable tests. Independent review before committing; Darwin/iOS coverage explicitly separate. No release until reviewed verification.
