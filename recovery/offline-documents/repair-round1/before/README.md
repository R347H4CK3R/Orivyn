# Jarvis-EVO offline document reader

Implemented in an isolated workspace for independent review. **Not integrated, Swift-compiled, native-tested, or released.** No files in the frozen Jarvis-EVO app tree were changed.

- `JarvisEVO/Services/`: five new Swift production files.
- `Tests/OfflineDocumentReaderTests.swift`: reader XCTest sources using actual synthetic packages.
- `Tests/OfficeAttachmentIntegrationTests.swift`: private-original/prompt/history/cleanup integration tests for the proposed patch.
- `Tests/OfficeFixtures/`: 49 deterministic tiny benign/adversarial fixtures and SHA-256 manifest. The ZIP-bomb fixture is small on disk and declares a 5 MiB repeated payload; production preflight rejects it before decompression.
- `proposed/office-integration.diff`: **proposal only**, for AttachmentService, file-picker types, and XcodeGen wiring.
- `INTEGRATION.md`: exact steps and required native verification.
- `DESIGN-AND-TESTING.md`: behavior, limits, remaining validation, and Linux evidence.
- `provenance/`: official ZIPFoundation 0.9.20 MIT license, verified commit/API provenance and source snapshots.
- `SOURCE-MANIFEST.json`: SHA-256 file inventory and frozen input hashes.

Public-facing capability: locally selected DOCX/XLSX text and stored cell values; UTF-8 CSV/TSV structured rows. No exact layout, image/scanned-page reading, formula evaluation, old DOC/XLS support, or remote runtime service.

API: `try OfflineDocumentReader().read(at: selectedOrPrivatelyStagedURL)` returns `OfflineDocumentResult` with `format`, bounded `text`, `notes`, `wasTruncated`, and `modelContext`. Put `modelContext` in the existing optional `ChatAttachment.extractedText`; no persistence schema change is needed.

Run the **non-native** evidence checks:

```
python scripts/generate_fixtures.py
python scripts/check_office_delivery.py
```

Neither command executes Swift or demonstrates that the iOS application builds.
