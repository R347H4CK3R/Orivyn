# Integration instructions (proposal, do not apply to the frozen candidate)

The coordinator should independently review and integrate only after the frozen candidate3 gate. This work has not changed that tree.

1. Verify the three frozen source SHA-256 values in `proposed/base-source-sha256.json` still match the intended integration tree. If they changed, rebase the small patch manually and review those differences. Do not blindly overwrite AppModel, Conversation, existing tests/scripts, or active project configuration.
2. Copy these **new** production files into the app target's `JarvisEVO/Services/`:
   - `OfflineDocumentReader.swift`
   - `OfficeZIPContainer.swift`
   - `BoundedOfficeXML.swift`
   - `OfficeTextExtractor.swift`
   - `DelimitedDocumentReader.swift`
3. Copy the two new XCTest files into `Tests/`, and the entire `Tests/OfficeFixtures/` folder into the same relative location. Do not overwrite old tests. These fixtures belong to the **test bundle only**, not the production app.
4. Review and apply `proposed/office-integration.diff` to the chosen non-frozen integration checkout. It changes only:
   - AttachmentService: recognize four supported extensions; stage an exact bounded immutable local snapshot under UUID + real extension; extract format notes/text; preserve the existing return/schema and failed-import cleanup.
   - FileAttachmentPicker: add extension-derived DOCX/XLSX/CSV/TSV UTTypes without broadening the picker to arbitrary data.
   - XcodeGen: add the pinned package/product and test folder resources.
5. Copy `provenance/ZIPFoundation-LICENSE.txt` into `ThirdPartyNotices/ZIPFoundation-LICENSE.txt`. Preserve the MIT notice in redistributed source/binary notices using the project's existing third-party notice procedure. API snapshots in provenance are review evidence, not files to compile into the app.
6. Resolve/generate/build using the project's normal XcodeGen/native workflow. Verify Package.resolved actually records the commit below, then run the two new XCTest classes and the existing attachment/picker/image/history/app regressions. Use a currently verified local iOS simulator destination, not a guessed simulator name. This authoring host cannot execute these steps.

## Exact dependency wiring

Official repository: https://github.com/weichsel/ZIPFoundation.git

Version verified: **0.9.20**

Exact immutable commit: **22787ffb59de99e5dc1fbfe80b19c97a904ad48d**

License: **MIT**, Thomas Zoechling and ZIP Foundation authors.

Add under XcodeGen `packages`:

```yaml
ZIPFoundation:
  url: https://github.com/weichsel/ZIPFoundation.git
  revision: 22787ffb59de99e5dc1fbfe80b19c97a904ad48d
```

Add under `targets.JarvisEVO.dependencies`:

```yaml
- package: ZIPFoundation
  product: ZIPFoundation
```

Change only the generic Tests source entry and add a test-only folder resource entry under `targets.JarvisEVOTests.sources`:

```yaml
- path: Tests
  excludes: [OfficeFixtures]
- path: Tests/OfficeFixtures
  type: folder
  buildPhase: resources
```

Preserve the other existing source/model-fixture/dependency entries. The folder reference is intentional: XCTest resolves `Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "OfficeFixtures")`.

## API integration contract

```swift
let reader = OfflineDocumentReader()
let result = try reader.read(at: userSelectedOrPrivatelyStagedURL)
// Save result.modelContext in ChatAttachment.extractedText.
// Preserve the bounded original bytes with format.rawValue extension and format.mediaType.
```

The proposal uses `boundedSnapshot(at:)` when staging, then `read(data:format:)` from the private original. Neither method uploads, runs Office code, or extracts archive entries into filesystem paths. Security-scoped URL access remains owned by AttachmentService's existing import method.

No new Codable property is required. `ChatAttachment` and `ChatMessage.promptContent` remain backward compatible; the latter already treats document text as untrusted. Limitation and cache/truncation notices are frontloaded in `modelContext` so the existing prompt cap does not hide them.

## Verification commands available here

```sh
python scripts/generate_fixtures.py
python scripts/check_office_delivery.py
cd /workspace/shared/Jarvis-EVO-recovery-next
git apply --check /workspace/shared/Jarvis-EVO-office-work/proposed/office-integration.diff
```

Those are fixture/contract checks and a patch dry-run, **not Swift tests or native build evidence**. Do not upload/push/publish or start CI simply to integrate this proposal without the coordinator's authorization.
