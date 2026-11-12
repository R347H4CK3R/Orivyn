# Offline desktop checkpoint integration

User scope: standalone iPhone desktop with actual guest execution, reliable persistence and no external computer runtime. Engineering choices below remain internal until licensed guest and native acceptance pass.

- Reuse the now-native-verified WKWebView/v86 boundary. Do not broaden CSP, enable workers/network, share host folders or embed other iOS apps.
- New maintained Linux graphical guest is built from signed/hash-pinned Buildroot sources with exact corresponding source and legal manifest; old TinyCore remains excluded.
- RAM-backed user HOME plus immutable guest/root identity makes a whole-VM checkpoint the initial persistence unit. No claim that external mutable disks are saved.
- Pause before snapshot; transfer at most128KiB per authenticated owner-scoped bridge message, maximum256MiB total. No single huge base64 string.
- Native actor stores a staged generation, computes/rechecks SHA256 and atomically changes the active pointer only after successful verification. Retain previous valid generation. Stale/cancelled owners abort unpublished transactions.
- Restore verifies engine, guest and configuration identity, complete file checksum and bounded size before allocation. Pin generation for every read, prevent interleaving generations, resume only explicitly after complete restore.
- Test malformed metadata, short chunks, wrong offsets, corruption, interrupted writes, expired owner, generation changes and relaunch. Actual disk roundtrip with a fresh emulator is required in addition to unit tests.
- Bind to the app only after native gate; visible UI distinguishes installed/verified guest from unavailable guest. Main app must not show a fake desktop or advertise completion on BIOS-only evidence.

Current host test proves BIOS RAM/CPU state survives disk checkpoint and fresh-engine restore. v86's diagnostic instruction counter is not part of saved architectural state; tests inspect actual restored RAM and instruction pointer instead. This is not native file-bridge or guest desktop acceptance.
