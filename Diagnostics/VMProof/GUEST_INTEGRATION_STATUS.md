# Internal maintained guest integration checkpoint

This isolated sibling harness contains the maintained disk, exact-identity asset exception,
128MiB RAM / 8MiB VGA, disk-aware checkpoint identity and separate checkpoint directory.
BIOS-only baseline in Orivyn/Diagnostics/VMProof remains untouched by this integration.
CSP, no NIC/network, no host directory and explicit Resume are preserved. A 180-second
proof deadline replaces the BIOS-only 60-second deadline in this isolated harness only.

Verified locally: 27 JS tests, 14 asset hashes; all722 corresponding-source package
checksums rechecked successfully. The source package records no missing archives, but
clean rebuild reproducibility and firmware binary correspondence remain unverified.
No CI launch, native compilation, native full guest success, physical device success,
shipping integration or release is claimed.

Next gate must add actual graphical desktop/editor input and fresh file read after
checkpoint/relaunch, retaining screenshots. Existing native tests only cover CPU and
checkpoint machinery and must NOT be described as complete desktop acceptance.
This image's immutable preload currently incurs large copies. Measure peak native and
WKWebContent memory before approving a physical phone release. Preserve the exact
small-asset caps for all assets except this single hash-pinned disk.

Publication remains blocked on corresponding-source/notices availability and approval.
Private Orivyn source must not be published to satisfy independent guest licenses.
