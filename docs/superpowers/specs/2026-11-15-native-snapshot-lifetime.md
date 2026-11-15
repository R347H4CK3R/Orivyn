# Bounded native-model snapshot cleanup

The native transcript path makes a verified private model copy. Normal resource destruction removes it, but process death bypasses deinit and leaves a large temporary file. Preserve the copied-byte verification and mmap lifetime.

Use a versioned ownership marker and nonblocking advisory per-directory lease. Serialize creation/cleanup with a root coordination lock. Only exact versioned UUID directory names, expected regular single-link files, current-user ownership, and exact marker bytes qualify. Never traverse symlinks or recursively delete; remove only the two known files through an opened directory descriptor. Unknown contents, malformed markers, active leases, old unmarked directories and source downloads remain untouched. Each cleanup pass inspects at most128 candidates with a rotating cursor; root directory enumeration itself is not bounded. Cleanup runs before a new snapshot is created. Lease deinit removes its own validated directory after model/context destruction.

Alternatives rejected: age-only cleanup can remove a live model; unrestricted prefix recursive removal can delete unowned contents; relying on OS temp eviction leaves the current problem. No broad startup deletion or migration of old unmarked copies is included.

Tests use synthetic bytes in isolated temp roots: stale removal, active preservation, normal owner release, malformed/unknown/symlink/hardlink preservation and multiple leases. Native engine integration needs separate Apple compilation and real model checks; portable tests are not iOS inference evidence.
