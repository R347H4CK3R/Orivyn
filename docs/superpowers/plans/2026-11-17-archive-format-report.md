# Archive Format Report Implementation Plan

**Goal:** Read-only local inventory shape reporting and safe explicit manual DAT imports.
**Architecture:** Pure bounded inventory summary, existing validated service context and manual supplemental transaction; selected verified bytes feed strict classification then existing decoders.
**Tech Stack:** Swift6, Foundation, SwiftUI, existing ImageIO/PDFKit and SQLite.
**Spec:** ../specs/2026-11-17-archive-format-report-design.md

## Global constraints
No automatic associations, no filename inference, no private uploads, <=10MiB selected media, preserve originals/edits/receipts, build22 unchanged.

## Review focus
- Inventoried filenames must not leak via report: fixed enums/counts only.
- Metadata presence must not imply schema support: explicit disclaimer.
- DAT polyglots/invalid signatures must fail actual decoder before commit.
- Late cancellation must clean only newly owned staging/import assets.
- Original receipt identity must remain archive/message/original path across classification.

## Tasks
- [ ] Add ArchiveFormatReport pure Summary helper and synthetic privacy/category tests. Observe failing tests, implement bounded categorization, rerun full Foundation.
- [ ] Add validated service formatReport accessor and host integrity/no-write tests; keep report independent of import eligibility.
- [ ] Add selected DAT classification/helper/service tests with RED/GREEN; actual native importer tests prove accepted bytes and rejected malformed content, receipt uses original path.
- [ ] Wire report into retained archive UI and AppModel without automatic sharing/import; clarify DAT potential eligibility and validation on import. Add native UI checks.
- [ ] Update version0.1.7/build23, native exact test count and metadata contracts. Independent review, full local suite, exact native/resource/host gate and package verification.
- [ ] Guarded publication and public IPA/catalog re-verification only after all gates pass; retain earlier releases/evidence.
