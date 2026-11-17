# Unreleased research plan

This legacy-parser plan is retained for research only. The build22 candidate excludes that parser and uses explicit manual file/message selection instead.

# Legacy Archive Attachment Supplements Implementation Plan


**Goal:** Attach one explicitly mapped supported local export file to an unchanged imported message after user review.
**Architecture:** Strict legacy static map parser; hash-bound retained candidate service; no-follow verified staging copy; existing attachment importer; separate immutable SQLite supplemental receipt; reviewed UI.
**Tech Stack:** Swift6, Foundation, CryptoKit, SQLite3, SwiftUI, existing image/PDF/text importers.
**Spec:** docs/superpowers/specs/2026-11-17-legacy-archive-attachments-design.md

## Global constraints
- Preserve original archives, text receipts, local edits, released build21 and unresolved counts.
- Legacy chat.html only; exact UUID message/path joins; no inferred mappings or network access.
- One explicit file per confirmation; supported image/PDF/text at most10MiB.
- No claims about current index.html exports or the user's actual backup.

## Review focus
- A script marker inside conversation text/comments must not become a map: parser adversarial tests.
- An edited/deleted target must never be overwritten/resurrected: database snapshot+epoch tests.
- Crash after commit must not duplicate or delete ownership: receipt replay and native relaunch tests.
- File mutation/symlink during copy must fail closed: descriptor/hash tests.
- Image relabeling cannot bypass provenance: importer+native preview tests.

## Task1: Static legacy mapping
Files: new Core/LegacyArchiveAssetMap.swift and Tests/LegacyArchiveAssetMapTests.swift.
- [ ] Pin real observed declaration syntax in cited research note.
- [ ] RED tests for exact map plus duplicate declaration/key, escaped duplicate, comments/strings, traversal, bounds and malformed shape.
- [ ] Implement `LegacyArchiveAssetMap.parse(_ html:Data)throws->[UUID:[String]]` with strict bounded nonexecuting lexical extraction.
- [ ] Run focused tests; independent parser review; commit.

## Task2: Supplemental persistence
Files: Core/ArchiveAttachmentSupplement.swift, Persistence/SQLiteConversationStore.swift and focused persistence tests.
- [ ] RED tests for append-only attachment, unchanged text receipt, exact replay, changed target, erased epoch, duplicate identity and rollback.
- [ ] Define source-bound review/receipt values and canonical identity binding.
- [ ] Add separate atomic apply/read receipt APIs without relaxing applyArchiveRestore.
- [ ] Run focused and aggregate persistence gates; review; commit.

## Task3: Retained candidate service and verified copy
Files: Services/ArchiveRestoreService.swift plus separate supplement service, ArchiveAttachmentAssociation.swift and service diagnostics.
- [ ] RED tests for exact supported visible UUID/path candidate, ambiguous maps/paths, hidden messages, changed hashes, unsupported formats, size limits, symlinks and cancellation.
- [ ] Read hash-bound job/map/plan/inventory without activating; paginate candidate metadata.
- [ ] Implement no-follow exclusive staging copy and byte/hash verification; reuse scoped read buffers.
- [ ] Validate staged supported bytes through existing importer; verify original output hash; cleanup only owned precommit files.
- [ ] Run portable host and native importer tests; review; commit.

## Task4: Reviewed UI and ownership coordination
Files: UI/ArchiveRestoreView.swift, UI/AppModel.swift, UI/SettingsView.swift and UI tests.
- [ ] RED native flow for candidate selection, explicit confirmation, actual preview after commit/relaunch, unchanged original count and cancellation.
- [ ] Wire bounded read-only candidate list and one-file review; serialize history changes and fence lifecycle changes.
- [ ] Commit with current snapshot/epoch; handle prior receipt before importing; preserve committed ownership across reload failure.
- [ ] Run native flow and aggregate gates; review.

## Task5: Verified release
- [ ] Update version/build/in-app information accurately after scope is verified.
- [ ] Full exact-source native gate, package verifier and independent review.
- [ ] Publish only verified IPA; update Distribution and Omni without altering other apps/history; verify live asset and feeds.
