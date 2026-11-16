# Original archive preservation proof

This component preserves an opaque source file. It does not establish that the file
is a valid ZIP, import history, resolve attachments, or mark an app release ready.

`ArchivePreservation.preserve(source:staging:)` requires a **nonexistent staging
child of a canonical app-private parent**. It creates original.zip exclusively,
uses 64 KiB chunks, checks size/free-space limits before copy, checks cancellation,
and SHA-256 hashes copy/source again before publishing verified-manifest.json.
Files, staging directory and its parent are fsynced before successful return.
Original source is never modified. Errors retain partial staging and do not
publish a verified manifest. The tiny manifest's .partial hard link remains.

Call `revalidate(staging:expected:)` before consuming a previously retained job.
Store the returned manifest in durable coordinator state and pass it as expected
where available. A manifest is an integrity record, not a cryptographic signature.
The coordinator must hold Files-provider read coordination/security-scoped access
for the whole operation and serialize work for each staging tree. Resolve trusted
app container aliases such as /var before constructing the private parent. Source
and staging paths with symlink components fail closed. Concurrent replacement of
ancestors is outside the contract; O_NOFOLLOW only protects final components.
Revalidation detects file corruption, not subsequent mutations after it returns.

SHA-256 uses CryptoKit on Apple and the official swift-crypto 3.0.0 implementation
(revision 629f0b679d0fd0a6ae823d7f750b9ab032c00b80) for the Linux proof.
Run from the repository:

```
python Diagnostics/ArchivePreservation/run.py /path/to/swift /new/scratch/test-package
```

Nine focused synthetic Linux Swift 6.0.3 tests pass: exact bytes/revalidation,
existing-output preservation, no-follow source handling, corruption/symlink
replacement, cancellation retention, size ceiling, independent SHA-256 abc vector
and expected-manifest binding, mutation during copy, insufficient-disk preflight
using a sparse synthetic file. The initial copy/cancellation/revalidation tests
failed against the unimplemented API before implementation. Independent review
identified the missing parent fsync; it is now included and regression suite rerun.

This is not Apple-native compilation, physical-device testing, real 2.44 GB archive
verification, a power-loss fault-injection test, or integration of the full app.
