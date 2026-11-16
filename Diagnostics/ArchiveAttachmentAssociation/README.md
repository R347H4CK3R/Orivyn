# Conservative archive asset association foundation

This component prepares associations; it does not copy assets, modify SQLite,
activate ChatAttachments, infer media types, or decode images. The actual private
ChatGPT `export_manifest.json` / `conversation_asset_file_names.json` schemas have
not been inspected here, so no parser for either file is invented.

The coordinator supplies explicit mappings from exact source identifiers to
extracted relative paths. Only `contentPart.asset_pointer` and
`attachmentMetadata.id` references are recognized. Unknown/malformed references,
missing or duplicate mappings, duplicate evidence, missing durable IDs, and UUID
collisions remain explicitly unresolved. All supplied reference JSON bytes remain
in the result, including unresolved records. References are never fetched as URLs.

`verify(root:relativePath:bytes:sha256:)` opens each child directory through
no-follow directory descriptors, rejects nonregular files without blocking on
FIFOs, bounds a file to 512 MiB, hashes in 64 KiB chunks and compares expected
size/SHA-256 plus source metadata before/after hashing. Only this verifier can
construct VerifiedFile evidence. The root must be a canonical app-private path
whose ancestors are stable under the coordinator's serialization. Evidence is
bound to that exact root and path, not only the filename.

`plan(root:references:mappings:files:identities:)` returns UUID-based opaque
`.archive-asset` copy plans, association indexes, and unresolved reasons. It does
not mint identities. The caller must persist an archive-scoped identity mapping
before retryable work and reverify expected hashes during copying, then register
ownership and compatible MIME/runtime metadata before activating an attachment.
A prior hash check is not a guarantee that a later read sees unchanged files.
Repeated references to one exact source ID share one planned copy. Originals must
remain preserved by the separate archive-preservation coordinator.

Limits: 20,000 references/mappings/files/identity entries; 1 MB per reference JSON;
16 MB aggregate reference bytes, mapping text, and identity-key text respectively;
4 KiB source IDs and relative paths; 64 path components. Oversized preparation
fails closed. Unsupported or >512 MiB assets remain preserved in the original
archive rather than being silently presented as imported attachments.

## Verification

Run only synthetic test data:

```
python Diagnostics/ArchiveAttachmentAssociation/run.py /path/to/swift /new/scratch/proof
```

Uses Apple CryptoKit or pinned official Swift Crypto 3.0.0 on Linux. Eleven focused
Swift 6 tests passed, covering exact association, expected SHA/size, traversal and
symlinks, ambiguous/missing data, repeated references, cross-root evidence,
duplicate identities/evidence, FIFO/directory rejection, limits and cancellation.
Initial association/verification tests and oversized-key test were observed failing
before their implementations. Independent review found no blocking issue within
the documented serialized-root and mandatory-copy-reverification contract.

Repository Foundation regression: 515 passed (native URLProtocol redirect test
remains excluded on Linux). Portable Python baseline remains 271 tests with
4 failures / 4 errors / 1 skip, unchanged: attachment fitting, explicit model gates,
persistence disclosure, picker contract, and missing guest-image fixture. This is
not a full app pass, Apple compilation, real export association or device test.
