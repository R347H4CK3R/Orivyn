# License and provenance audit: internal prototype, NOT release approval

## Pinned engine and firmware

- Official `v86@0.5.473`, package version `0.5.473+g315b2b0`, source commit `315b2b0b758703ef0e6cc7b4088d6068f83f3c20`. Package SHA-512 integrity and decoded npm provenance agree with the official GitHub repository/commit. This is **not** a claim of independent Sigstore cryptographic verification. `npm pack --ignore-scripts` downloaded it; no package install scripts ran.
- v86 is BSD-2-Clause. Its exact source archive is retained. Bundled SoftFloat release 3e contains BSD-3-Clause-style notices; Zstandard 1.4.5 decompressor permits choosing BSD rather than GPL. `LICENSE.MIT` also covers the attributed MIT component. Preserve the actual notices, not just a package-name list. No external Rust crate dependencies appear in this pinned Cargo.toml.
- SeaBIOS and VGA BIOS come from that same v86 tree. The tree's `fetch-and-build-seabios.sh` pins **SeaBIOS rel-1.16.2**. The exact release source archive, LGPLv3 license text, v86 configuration and build script are retained. Reproducible binary correspondence has not been independently rebuilt; preserve source/configuration/notices and review any LGPL requirements before distribution.
- `PINNED_ASSETS.json` records SHA-256 and byte lengths for all runtime binaries and primary source archives. Its `distributionApproved` is false.

Primary sources:
- https://github.com/copy/v86/tree/315b2b0b758703ef0e6cc7b4088d6068f83f3c20
- https://registry.npmjs.org/v86/-/v86-0.5.473.tgz
- https://github.com/coreboot/seabios/tree/rel-1.16.2

## Guest audit and actual blocker

TinyCore 11.0 came from its official ibiblio archive and matched the publisher's MD5 file. SHA-256: `778fc3788d9df3de72970827968b2b195aca827401db6f6f9cbdb737d4300bda`. Size 19,922,944 bytes. Published MD5 detects accidental differences; it is not a modern independent authenticity signature.

- ISO inventory/hashes: `audit/iso-files.json`.
- Parsed initramfs inventory/hashes: `audit/core-files.json`. It identifies TinyCore 11.0 and includes GPLv2, GPLv3, BSD and GFDL license texts, but this alone is not full source compliance.
- All 24 embedded graphical extension packages were matched against their embedded checksum files and current official 11.x package metadata. `audit/guest-package-audit.json` retains the comparison.
- **19** current repository MD5 values still match the ISO packages. **Five do not:** `fltk-1.3`, `flwm`, `libpng`, `wbar`, `Xlibs`. Their current metadata therefore cannot be treated as exact historical version evidence.
- Official Xvesa metadata says GPL; aterm and wbar say GPLv2; FLWM says GPL. Xprogs/FLTK say only “OpenSource”, which is not a sufficiently specific license clearance. Do not assume that every X/GUI component is MIT.
- Official sources are discoverable for the core kernel 5.4.3 + TinyCore patches/config, BusyBox 1.31.1 + patches/config, and glibc 2.30/toolchain, but a complete matched corresponding-source bundle for the ISO has **not** been assembled or verified.
- The distribution is EOL. Offline isolation reduces exposure but does not turn it into a maintained release guest.

Official guest/source indexes:
- https://distro.ibiblio.org/tinycorelinux/11.x/x86/archive/11.0/
- https://distro.ibiblio.org/tinycorelinux/11.x/x86/release/src/
- https://distro.ibiblio.org/tinycorelinux/11.x/x86/tcz/

**Decision: preserve this ISO as private research; exclude from Orivyn source commits, IPA, distribution and public demos.** Prefer a new reproducible guest rather than inferring old binary licenses.

## Private application source

The proposed boundary uses a permissive emulator and independent Linux guest programs, not a GPL QEMU library linked into Orivyn. That avoids deliberately creating the known GPL-QEMU combined-work issue. It is not a legal ruling that every distribution detail is exempt: provide corresponding source, patches, build configuration, notices and applicable modification/installation rights for the components actually shipped, and review the final packaging. No private application code or research image has been published.
