# Design and testing report

## Outcome and verification boundary

The implementation is ready for independent source review and later native integration. It is **not a shipping/passing native candidate**. This Linux host has no `swift`, `xcodebuild`, or `xcodegen`. The Swift sources, Foundation/XMLParser delegate behavior, Apple Compression/ZIPFoundation execution, XCTest resource discovery, native picker, preview, and iOS strict-concurrency build have **not** been compiled or exercised here.

Verified on the authoring host:

1. 12 independent Python fixture/contract checks pass. These check the synthetic fixture bytes, a separate ZIP32 metadata oracle with zlib streamed-size/CRC checks, XML attack intent, valid DOCX/XLSX contents, actual formula/type coverage, relationship attack intent, CSV semantics, source guard presence, dependency provenance, native-test fixture references, and unchanged frozen patch inputs. **The Python oracle is not the Swift implementation.**
2. The proposed XcodeGen YAML parses and asserts the exact package commit, product dependency, and test-folder resource wiring.
3. `git apply --check proposed/office-integration.diff` passes against the frozen input tree, without applying it.
4. Official ZIPFoundation tag 0.9.20 resolves to commit `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`. License and exact public APIs were read via the read-only GitHub connector. This is dependency/API provenance, not a native package build.
5. Generated fixtures are deterministic, locally synthetic, and contain no user documents or credentials. No runtime network access, document upload, account setup, paid service, CI job, repository write, or user contact was used.

The native XCTest sources and initial 29 real ZIP/XML/text fixtures were written before the production services. Native red/green execution was unavailable. Coverage was expanded to 49 fixtures during implementation. The Python checks initially exposed two incorrect checker assumptions (a temporary symlink name was mistaken for a bundled fixture, and a long XML string was expected to fail the ZIP ratio before its actual XML-string limit); both checker expectations were corrected using measured bytes and rerun successfully. No native success is inferred from this.

## Architecture

- `OfflineDocumentReader.swift`: format/result/error/limit API, O_NOFOLLOW + fstat + chunk-bounded local input snapshot, output budget, visible escaping of control characters.
- `OfficeZIPContainer.swift`: strict ZIP32 metadata preflight, then official ZIPFoundation in-memory Archive + streaming consumer. No archive entry is extracted to the filesystem. Every entry, including ignored binary/image parts, is streamed under real-byte and CRC checks; only XML/relationship bytes are retained.
- `BoundedOfficeXML.swift`: UTF-8-only, no-DTD/no-entity XML parser. Resolves qualified element and attribute namespaces explicitly. Bounded nodes/depth/text/attributes/string lengths. External entity callbacks abort; no remote resolution exists.
- `OfficeTextExtractor.swift`: contained OPC relationship resolution plus known main content types. DOCX body paragraphs/tables; XLSX sheet names, sparse row/cell coordinates, shared/inline/rich/escaped strings, numbers, booleans, errors, dates, and stored formula caches. No formula expression is executed or used to invent a value.
- `DelimitedDocumentReader.swift`: strict quote-state UTF-8 CSV/TSV parser, embedded newlines/quotes, trailing empty fields, explicit row/column labels. Retains bounded output while validating the entire bounded input. It does not infer a header row or evaluate leading `=` text.

### Alternatives considered

- Hand-written ZIP decompression: rejected. It duplicates a security-sensitive codec and contradicts the brief.
- Heavy Office-rendering/parser framework or web conversion: rejected. It adds a large runtime/dependency surface or uploads selected content, and is unnecessary for the existing text-only model.
- Official MIT ZIPFoundation + a strict metadata gate + bounded Foundation XML extraction: chosen. The metadata gate is needed because encryption is not public on Entry, iteration can omit unsupported/encrypted records, and extract returns a calculated CRC that callers must compare themselves.

## Safety profile and ceilings

Hard ceilings cannot be raised through the API; callers may only lower them:

- Input snapshot: nonempty regular file, 10 MiB maximum, 32 KiB file-read chunks, no final-component symlinks.
- ZIP: 512 entries; 4 MiB per expanded entry; 32 MiB expanded total; maximum 200:1 expansion per entry; stored/deflate ZIP32 only.
- Decompression: 16 KiB buffers, real callback-byte checks against both declared and hard sizes, exact observed final size and CRC match, bounded callback count and at most eight consecutive empty callbacks, cancellation checks.
- XML per processed part: depth 64, 80,000 nodes, 2 MiB text, 32 attributes per node, 32 KiB individual string, at most 32 namespace bindings. All parts remain under the ZIP total bound. XML parts not used for document extraction are never parsed or executed.
- Workbook: 20,000 shared strings, 32 worksheets. Output is limited to 1,000 rows and 10,000 cells across sheets, plus 60,000 text characters. Huge sparse coordinates do not allocate grids. Invalid, duplicate or decreasing row/cell coordinates are rejected.
- CSV/TSV: same 10 MiB input, 32 KiB field, 1,000 output rows, 10,000 output cells, and 60,000 output characters. Oversized fields fail; omitted output is explicitly marked truncated.

ZIP preflight rejects encryption, unsupported flags/methods, ZIP64/multi-disk, unsafe/absolute/archive paths, percent/URI/backslash ambiguity, duplicate/case-colliding names, symlinks and special Unix file types, local/central disagreements, overlap/gaps, malformed extras/descriptors, resource bombs, executable Office parts such as VBA/ActiveX/OLE binary embeddings, and integrity mismatches. It checks metadata only; it does not implement compression. ZIPFoundation decodes the stream. This is a deliberately strict supported profile, not a complete Office/ZIP conformance validator.

Internal relationships resolve to package dictionary keys, never filesystem/network locations. Rooted **OPC part URIs** such as `/xl/workbook.xml` are safely stripped to a package key, not treated as OS absolute paths. Relative parent segments are allowed only when the canonical result stays within the package, so ordinary `../styles.xml` references can work while package-root escapes fail. Percent encoding, schemes, query/fragment ambiguity and missing targets fail. External hyperlinks are ignored and disclosed; other external relationships (including external worksheets/images) fail.

## Honest text semantics

- Notes precede content in `modelContext`, so the current 20,000-character per-document prompt cap retains the limitations. The existing 60,000-character saved extraction cap remains unchanged in the proposal. Result truncation is explicit, and the older AttachmentService truncation marker still applies when its combined notes/text cap is reached.
- DOCX: meaningful paragraph breaks, tabs, line breaks and table rows/cells. Body-only transitional WordprocessingML. No claim of exact layout, list numbering, image/scanned content, headers/footers, comments, footnotes, text boxes, drawings, deleted text or field instructions.
- XLSX: transitional SpreadsheetML worksheet values, including hidden sheets and rows with labels. Shared/inline rich strings exclude phonetic annotations. `_xHHHH_` UTF-16 escapes are decoded once; literal underscore escape sequences and surrogate pairs are handled, invalid UTF-16 is rejected.
- Numeric spelling is retained rather than round-tripped through floating point. Nonfinite/invalid numeric caches fail. Boolean, error and ISO date cells are labeled. Date/time-formatted numeric values retain their raw serial, workbook 1900/1904 epoch and format identifier. Excel serial 60 is not converted into a fabricated Gregorian date. Custom number formats stay annotations, without assuming every custom format is a date.
- Formula caches are labeled cached/may be stale. Missing caches are labeled unavailable, including shared-string formulas. An explicitly empty cached string is distinguished from a missing numeric cache. Formula bodies are not emitted as computed facts or executed.
- Charts, images, scanned pages, merges, filters and formatted layouts are not interpreted. Non-worksheet sheets, old binary DOC/XLS, macro-enabled variants, UTF-16 Office XML, non-ASCII archive entry names, unsigned ZIP descriptors and unusual ZIP profiles fail honestly rather than being claimed supported. This conservative reader can reject otherwise legitimate documents containing unsupported embedded/printer binary parts or linked content.

## Original-attachment compatibility

The proposal preserves a random UUID filename and an exact bounded private original snapshot with its real `.docx/.xlsx/.csv/.tsv` extension and MIME type. Extraction failure removes the staged original. Original source access remains within the selected file's existing security-scope grant. The serial importer actor, cancellation/ownership pipeline, image provenance, preview behavior, and ChatAttachment Codable schema are unchanged. No AppModel or Conversation change is proposed. Existing PDF/text/image routes remain available.

## Required next gate

An independent review and native Swift 6/iOS 26 compilation/test run are required before integration is considered validated. Run both new XCTest classes plus existing attachment, picker ownership, image provenance, persistence/history, prompt/context and app/UI regressions. Confirm test-folder bundle lookup, exact original bytes after source removal, repeated imports, cancellation/cleanup, native picker availability and preview. No native test count or runtime performance/safety guarantee is asserted here.
