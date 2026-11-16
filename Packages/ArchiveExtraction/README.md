# Bounded ZIP extraction foundation

This Swift package uses the operating system's zlib through a small C wrapper. It does not use ZIPFoundation or load archive contents into memory. It is not yet wired into Orivyn's Files UI or restore database transaction.

## Contract

```swift
let entries = try ZIPExtractor.extract(
    source: staging.appendingPathComponent("original.zip"),
    destination: staging.appendingPathComponent("extracted"),
    cancelled: { cancellationFlag }
)
```

- The caller owns a canonical app-private staging parent, without concurrent ancestor replacement. `destination` must not exist. Original input is opened read-only/no-follow/nonblocking and must be a regular file.
- The caller first preserves/revalidates the original SHA-256 manifest. This extractor verifies metadata, exact decompression boundaries, CRC and written bytes, but CRC is not a cryptographic authenticity check.
- Source, destination, and partial outputs are never deleted on failure. A retry uses a fresh destination. Per-member resume is not implemented.
- Parent directory links and output files are flushed. This is not complete crash recovery: the coordinator must rehash/reverify files, maintain its own durable state, and publish atomically only after verification.
- Synchronous extraction belongs on a utility worker, not the UI actor. Cancellation is cooperative during metadata processing and every 64 KiB extraction/output verification chunk. Source `Task` cancellation and the supplied callback are recognized.
- Entries return `path`, uncompressed `bytes` and `crc32`. Directories end in `/` and return zero bytes. The coordinator owns SHA-256 output manifests, content interpretation and attachment ownership.

## Accepted / rejected inputs

Accepts single-disk ZIP/ZIP64, stored and raw-deflate members, UTF-8/ASCII filenames and correctly bounded optional data descriptors. Rejects encryption, unsupported methods, malformed/ambiguous metadata, inconsistent local/central fields, special Unix file types, unsafe names, case/canonical Unicode duplicates, file/directory ancestor conflicts, overlapping member regions, CRC errors, truncated/nonfinal streams and trailing compressed data. Some uncommon valid ZIP encodings are deliberately unsupported; a failure must preserve the original for another reader, not silently skip entries.

Defaults: 20,000 entries, 64 MB central directory, 4 GB maximum expanded member and 20 GB cumulative expanded data, with a 64 MB free-space reserve. Before destination creation, expanded bytes plus reserve must fit the parent filesystem's available capacity. Concurrent disk consumption can still cause ENOSPC during writes; that failure retains staging and original bytes. The application should select lower limits based on device resources. Input/read/output buffers are bounded; metadata collections are bounded by entry/name limits. ZIP64 support is verified with synthetic small ZIP64 metadata, not an actual multi-gigabyte user archive.

## Validation

On Swift 6.0.3/Linux with system zlib 1.3.1: 17 XCTest tests pass. These cover stored/deflated output, ZIP64/descriptors, source retention, path/canonical/ancestor attacks, exclusive destinations, CRC and size limits, encryption/symlink/FIFO/special types, nested valid-header overlap, strict deflate termination/input consumption, expansion beyond advertised output, multi-chunk output draining cancellation retaining staging, and insufficient-capacity rejection before destination creation.

The FIFO test was observed timing out before the nonblocking-open fix, then passing. The C shim compiles with `-Wall -Wextra -Werror`. No private archive, iOS compilation, physical device, or whole-app restoration verification is implied.

```sh
swift test --jobs 2 --package-path Packages/ArchiveExtraction
cc -Wall -Wextra -Werror -I Packages/ArchiveExtraction/Sources/CArchive/include \
  -c Packages/ArchiveExtraction/Sources/CArchive/archive.c -o /tmp/orivyn-archive.o
```
