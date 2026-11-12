# Jarvis-EVO offline document reader

Implemented in an isolated workspace for independent review. **Not integrated, Swift-compiled, native-tested, or released.** No files in the frozen Jarvis-EVO app tree were changed.

- `JarvisEVO/Services/`: five new Swift production files.
- `Tests/OfflineDocumentReaderTests.swift`: reader XCTest sources using actual synthetic packages.
- `Tests/OfficeReviewRegressionTests.swift`: byte/memory/style/formula-range/stage/cancellation/FIFO/compatibility regression sources.
- `Tests/OfficeAttachmentIntegrationTests.swift`: private-original/prompt/history/cleanup integration tests for the proposed patch.
- `Tests/OfficeFixtures/`: 74 deterministic small-on-disk benign/adversarial/library-exported fixtures and SHA-256 manifest. The ZIP-bomb fixture is small on disk and declares a 5 MiB repeated payload; production preflight rejects it before decompression.
- `proposed/office-integration.diff`: **proposal only**, for AttachmentService, file-picker types, and XcodeGen wiring.
- `INTEGRATION.md`: exact steps and required native verification.
- `DESIGN-AND-TESTING.md`: behavior, limits, remaining validation, and Linux evidence.
- `provenance/`: official ZIPFoundation 0.9.20 MIT license, verified commit/API provenance and source snapshots.
- `SOURCE-MANIFEST.json`: current active-file SHA-256 inventory, frozen input hashes and repair-package pointers.
- `repair-round1/`: exact local before snapshot, focused after copies/diff, review mapping and check logs.

Public-facing capability: locally selected DOCX/XLSX text and stored cell values; UTF-8 CSV/TSV structured rows. No exact layout, image/scanned-page reading, formula evaluation, old DOC/XLS support, or remote runtime service.

API: `try OfflineDocumentReader().read(at: selectedOrPrivatelyStagedURL)` returns `OfflineDocumentResult` with `format`, bounded `text`, `notes`, `wasTruncated`, and `modelContext`. Put `modelContext` in the existing optional `ChatAttachment.extractedText`; no persistence schema change is needed.

Run the **non-native** evidence checks:

```
python scripts/generate_fixtures.py
python scripts/check_office_delivery.py
python scripts/check_review_delivery.py
```

These commands do not execute Swift or demonstrates that the iOS application builds.
