# Maintained guest native gate

Scope: internal acceptance only, not a production feature or release claim.
The existing BIOS-only harness remains the baseline while the checkpoint gate runs.

The maintained guest has a real Fluxbox desktop, xterm and xedit. A host test now
saves text in xedit and proves a fresh read after engine destruction/snapshot restore.
Disk SHA-256: 0897e5f867267c209f2866e2ee960971caf25886eb0345fe2f514b11e19cf0f1
Disk size: 135266304 bytes. gzip -n fixture SHA-256:
e3f9b8a21f15d7dcfca9c30caeb268b7d443027ae46d2f2ecff260c4f91e8815

## Next implementation boundary

1. Keep BIOS default. Add an explicit, internal maintained-guest profile only after
   source bundle/notices correspondence is assembled. No public binary-only guest.
2. Permit precisely the pinned guest asset, not a general large-file route. Existing
   small-asset cap and immutable-read/hash validation remain for all other files.
   Reject wrong hash, oversize, symlink, missing asset before constructing WebKit.
3. Guest profile uses128MiB RAM,8MiB VGA, no NIC, no shared host directory, unchanged
   restrictive CSP and nonpersistent browser storage. Checkpoint identity includes
   disk hash, engine variants and exact configuration, never BIOS identity reuse.
4. Do not pretend cold boot preserves RAM-home changes. Whole-machine checkpoints
   are the documented persistence unit; restore stays paused until explicit Resume.
5. Native UI test must observe real desktop pixels, enter/save a unique file through
   actual guest input, checkpoint, terminate/relaunch app, restore, and verify a fresh
   guest file read. Include wrong guest identity, corruption, background, interrupted
   save and repeated Stop/start tests. Instruction count alone is not desktop proof.
6. Measure large-asset and checkpoint memory, bridge throughput and UI responsiveness.
   Do not infer physical iPhone performance from host/simulator measurements.
7. Keep source/copyright/license/vulnerability gates explicit. No network-enabled
   guest or remote computer fallback is authorized by this plan.

## Release boundary

Passing this internal gate will not finish Orivyn1.0.0: shipping app resource
ownership, user-visible desktop input/storage controls, model/tool features,
external-display testing and physical iPhone verification remain required.
