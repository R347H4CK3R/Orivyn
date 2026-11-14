# Actual SQLite persistence acceptance

`run_persistence_tests.py` now compiles the exact production conversation/memory values and SQLiteConversationStore with official SQLite 3.50.4 source and executes the existing Swift XCTest fixtures. No database mock, replacement store or rewritten test definitions are used. Input source is explicit and the runner does not download dependencies.

A narrow refactor moved the unchanged ImageOCRResult value enum into Core and moved the same 10 MiB constant into ChatAttachment.maximumImageBytes. ImageAttachmentService aliases it. This removes the value models' dependency on Apple-only image execution without changing stored fields or limits. Independent review found no concrete behavior change. Proof47 records the original missing image-type dependency; proof46 was an earlier harness cache-path error, not an app defect.

Proof50 passes 23 actual XCTest cases: 13 persistence, 7 conversation value, 1 search, 2 OCR evidence. Includes actual database reopen, interrupted stream recovery, archive visibility, 20+ MiB backup roundtrip, malformed/oversized import rejection, memory ordering, embedded NUL search, preserve-local conflicts and cancellation. A new trigger-induced memory write failure verifies that earlier conversation replacements/additions roll back and a subsequent retry succeeds. An isolated copy with ROLLBACK removed fails four assertions/errors; restored exact production sources pass all 23 tests again.

Official source: https://www.sqlite.org/2025/sqlite-amalgamation-3500400.zip
Downloaded archive SHA256: 1d3049dd0f830a025a53105fc79fd2ab9431aea99e137809d064d8ee8356b032.
SOURCE-MANIFEST.json records exact source/header hashes. This is locally computed integrity evidence, not a separately verified vendor signature. SQLite is compiled in the isolated test package; the iOS application's system SQLite dependency is unchanged.

134 Python checks pass; the prior 250 Foundation XCTest cases remain unchanged. Thus 273 distinct Swift XCTest cases have now executed, plus previously separate smoke checks. Native iOS file protection, app integration, Apple OCR, UI, simulator, device and IPA remain unverified. Linux SQLite version need not match iOS's SQLite. No paid CI or release/catalog update occurred.

## Shared image identity checks

Three additional pure storage tests exercise actual SQLite connections with synthetic image metadata: conflicting shared-branch save preserves prior records; two independently connected stores launched in concurrent tasks yield exactly one saved row and one unsafe-attachment rejection; partial conflicting import rejects before any writes while replacing every shared reference consistently commits and survives reopen with its memory note. Concurrent scheduling does not force actual lock contention. This does not test image bytes, private provenance, previews, decoding, or rendering. Actual mid-write rollback remains covered separately by the trigger test above.

Proof53 passes all26 tests, bringing distinct executed Swift XCTest cases to276. New tests are also listed in the manual Apple acceptance gate, which remains unrun. Review feedback strengthened whole-row and reopened-memory assertions and corrected the pre-write rejection wording.

## Fixed mixed-snapshot exports

Independent review reproduced a real integrity defect: exportData read conversations and memories without a shared read transaction, so a second connection's atomic import could commit between them. The resulting backup mixed generations that never coexisted. The new test failed against original production code with conversation generation2 and memory generation3 (proof58).

Export now performs both reads and bounded encoding inside one deferred read transaction, committing only after success and rolling back any read/encoding/size/commit error. Actor isolation only protects one connection, so this transaction is necessary even though export has no suspension point. A second test corrupts fixture payload bytes, verifies export failure, and verifies same-store repair and subsequent writes after rollback.

Proof59 passes28 actual SQLite/value XCTest cases. Independent original repro rerun against fixed production completed200 iterations without mismatch. This bounded concurrent stress is evidence, not exhaustive scheduler proof. 134Python tests also pass; total distinct Swift XCTest count is282 with the prior254Foundation suite.

Related model investigation tested a positive source-inspection prompt without modifying production. It improved one UI-guidance answer but still had ambiguous future-access wording and generic refusals on a latest-commit holdout. No invented commit was observed. That experiment is not a claim of model reliability or a committed prompt fix; the explicitly reviewed navigation path remains the reliable implemented alternative. Its loopback servers were stopped.

## Reject duplicate attachment identities

A new malformed-backup reproduction showed duplicate document UUIDs (and mixed document/image UUIDs) were accepted in one message even though MessageRow uses all attachment IDs for SwiftUI identity. The validator previously checked only image IDs. It now checks every attachment ID within each message for both save and import, using the existing unsafeAttachment failure. IDs may still be shared across distinct messages/branches; no historical records are rewritten.

Proof60 failed8 assertions on the original code; proof61 passes all30 tests, including both malformed cases, unchanged database/memory on rejection, and valid cross-message sharing.134Python tests pass. Total distinct Swift XCTest count:284. This proves new-write/import validation, not an observed iPhone rendering defect or migration of already stored malformed data. Independent review confirmed the narrow scope.

## Reject backups that the same app cannot restore

Actual reproduction saved10001 notes and exported977702bytes, but importing the export failed because imports cap each collection at10000 while export checked only bytes. Export/import now share ConversationBackup.maximumRecordsPerCollection. Over-count export returns a clear error before encoding while retaining all data and releasing its read transaction. Nothing is truncated, deleted, or blocked from ordinary local saves.

Actual RED evidence records two expected failures for10001notes/conversations. GREEN passes32XCTest cases, including exact10000conversations+10000memories roundtrip, independent over-count exports rejected, full original counts retained, and a subsequent same-connection write succeeding.134Python tests pass; distinct Swift XCTest total is286. Segmented export above that size is not implemented; no unusable backup is silently delivered.
