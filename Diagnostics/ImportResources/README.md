# Synthetic import resource gate

Run `python3 scripts/run_import_resource_probe.py --swiftc "$(xcrun -f swiftc)" --output "$RUNNER_TEMP/import-resource-evidence"` on Darwin, or pass an installed Linux Swift compiler.

The script hashes and copies the exact production stream/projection/converter plus model dependencies and compiles an optimized host executable. A separate generator process creates synthetic inputs so its memory does not contaminate child high-water RSS. Each measured case is a fresh process. RSS is normalized from Darwin bytes / Linux KiB; the ceiling is 256 MiB.

Cases: a roughly 503 MB stream of 10,000 records verifies bounded repeated reads; 10,000 small valid records with 2,000-character payloads must all convert without retaining prior results; a 15.9 MB record with 279,000 unused metadata dictionaries must produce exactly one expected visible message; malformed unknown JSON must reject before activation; a 20,001-element opaque payload must give the actionable complexity error before activation. No network, private input or user history is touched. This does not test ZIP extraction, SQLite, iPhone UIKit or jetsam.

Original Linux baseline for the dense record: 907 MB peak RSS in `ChatGPTRecordStream` Foundation validation alone. Selected-field projection: approximately 50 MB peak RSS on the same host. This is a reproducible synthetic resource issue, not proof of the user's observed app exit.

Selected/retained structure ceilings: 100,000 projected value nodes, 16 MB retained scalar/key bytes, 20,000 opaque value nodes, 2 MB total opaque bytes, 20,000 mapping members, 20,000 parts, 2,048 attachments, depth 128 and numeric tokens up to 1,024 bytes. Unknown fields do not consume projected node budgets; they are still checked for valid syntax, Unicode and finite numeric values. Limits reject with an actionable error; the service keeps its original archive separately. Unknown duplicate keys are ignored; duplicate selected keys/mapping IDs, including escaped aliases, fail closed. Foundation parses only bounded selected scalar/opaque values.

RSS lookup failures fail the gate rather than reporting zero.

The scalar Foundation autorelease scopes and service per-record autorelease scope require native verification. The unchanged separate `FolderMemoryImport.chatGPT` full-array legacy path is not covered by this fix.

The separate production preservation gate runs 32 MiB and 2.2 GB copies plus cancellation in fresh macOS processes, requiring less than 64 MiB peak RSS, verified bytes and bounded display progress. These host probes are not physical-device proof.
