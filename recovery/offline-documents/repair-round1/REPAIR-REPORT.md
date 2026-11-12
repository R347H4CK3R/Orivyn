# Office review repair round 1

Result: scoped source repairs complete for independent re-review. **Not native-compiled, native-tested, integrated, or released.** Main candidate/AppModel/Conversation/active config and existing app test/script trees are unchanged.

## Review mapping

- **I1:** One incremental output sink charges every rendered UTF-8 byte, label and escape (240,000 bytes; conservative 60,000 Unicode-scalar ceiling). Saturation seals the prefix. No pre-cap row arrays/joins or complete escaped shared-string copies remain; custom format strings share storage. Cell/input validation continues after saturation without redundant rendering. Repeated-32-KiB, combining-mark, late-invalid-data, per-format, seal-prefix and native allocation/time regression sources added.
- **I2:** Explicit and omitted style index 0 follow one path. Row/column inherited format metadata is validated and explicitly marked unresolved, with frontloaded notes; no unverified precedence is inferred. Date/custom equivalence and inheritance fixtures/tests added.
- **I3:** Array/shared/data-table result followers use validated sparse rectangles, with cached/missing-cache labels. No formulas execute and no dense range/grid is allocated. Hard caps: 256 ranges per sheet; 1,000,000 cells per range; 1,000,000 charged overlap/membership comparisons across the workbook. Bad coordinates/anchors, overlap, excessive ranges/area/work fail honestly. Range/counter regressions added.
- **I4:** Bomb, entry/total/ratio and true overlap fixtures now isolate their named boundaries. Native tests assert exact internal error stages, not merely any throw. Deterministic current-Task cancellation hooks test decompression/cell validation and importer post-stage/extraction cleanup. The nil default hook only checks Task cancellation and cannot relax validation. No external setting was added. Three clean library exports add interoperability evidence without claiming native Office execution.
- **M1:** O_NONBLOCK + same-handle fstat; non-hanging FIFO regression source.
- **M2:** Actual bounded declaration-only encoding parse, with legal spacing/no-encoding/misleading-comment fixtures.
- **M3:** Defined Deflate level bits and bounded empty Deflate streams accepted; all other dangerous/unknown flags still rejected, real-byte/CRC/progress checks retained.
- **M4:** Narrow inert printer-settings name exception with bounded streaming/CRC and explicit ignored-content note. Macro/ActiveX/OLE rejection remains; other binary parts receive an honest unsupported error/workaround. Synthetic printer fixture only, no native printer interoperability claim.

## Evidence

- 12 original independent Python checks + 12 review checks: **24/24 pass**. These verify fixture intent, separate ZIP/zlib/XML/rendering references and source contracts, **not the production Swift execution**.
- 74 small-on-disk fixtures; deterministic byte regeneration verified. The repeated-large-shared XLSX is 61,550 bytes on disk with 10,000 references to one 32,768-byte string. The old row-render path implied 327,680,000 repeated raw value bytes before escapes/temporaries; this is source-derived, not a native measurement.
- Exact attack-stage oracle outcomes: entry-size -> declaredEntryBytes; total-size -> declaredTotalBytes; bomb -> declaredExpansionRatio; overlap -> archiveOverlap; forged-small-size -> streamedDeclaredBytes; bad-crc -> archiveIntegrity.
- Exact producer versions: python-docx 1.2.0, openpyxl 3.1.5, XlsxWriter 3.2.9. Their fixture XML/parts are unchanged except fixed core created/modified times, with normalized ZIP metadata; see provenance/fixture-producers.json.
- Python AST and proposed YAML package/product/resource assertions pass. Proposed integration patch `git apply --check` passes. All three frozen base hashes equal the pre-repair values, not merely newly regenerated references.
- Exact 73-file local pre-repair snapshot/hashes retained under before/. Focused added/changed after copies and file modes/hashes, text diff and change manifest are provided. SOURCE-MANIFEST.json inventories current active deliverables and points to repair proof. Snapshots are not integration inputs.

## Remaining mandatory gate

No swift, Xcode, Word, Excel or LibreOffice is available here. **38 XCTest method sources have not been compiled or executed**, including the memory/time and cancellation/cleanup tests. No native peak allocation, latency, cancellation, XMLParser/Darwin/ZIPFoundation execution, UI/picker/preview, or Office-app interoperability pass is claimed.

The coordinator must independently re-review this repair, then integrate only into an authorized non-frozen checkout and run Swift 6/iOS 26 compilation, exact package resolution, all three new test classes plus existing attachment/picker/image/history/prompt/app regressions, and real simulator/device resource/cancellation measurements. Native Office/LibreOffice exports and representative native printer-settings files remain a distinct interoperability gate. No CI, push, build or publication was started by this repair.
