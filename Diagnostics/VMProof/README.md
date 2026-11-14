# Orivyn native BIOS-only proof

**Isolated internal prototype, not a virtual desktop release.** Native BIOS execution passed at `49e49913`; subsequent checkpoint changes remain native-unverified. No shipping-app integration or new IPA publication has occurred. See the latest verification section below.

`./verify.sh`: five owner/lifecycle/input policy tests plus an actual pinned v86 BIOS execution test. Tests first failed on the missing controller, then passed. The real host test uses the bundled engine, WASM and ROMs, executes >100,000 guest instructions, and verifies there is no emulated NIC/relay. `BIOS_HOST_RESULT.json` records the actual instruction count and host memory; it is not iPhone evidence.

`materialize_assets.py` can recover the four exact engine/ROM assets from the pinned official npm archive and exact GitHub source commit during development. It rejects redirects, oversized responses, package/hash changes and nonregular archive members. It is not included as app executable code or called at runtime. The four generated assets are git-ignored; do not upload compiled blobs merely to run this proof.

`run_native.sh` is a prepared XcodeGen/iOS 26 Swift 6 native test command. It runs Swift policy/storage/bridge tests and actual UI tests: system-WebKit BIOS/WASM execution with retained screenshot, explicit Stop, and background without automatic restart. No fixture CPU output or screenshot is injected. The BIOS-only gate has run on CI as recorded below; new checkpoint tests remain unexecuted. No local Xcode/Swift Apple SDK is available. The parent owns the free CI budget.

## Boundary
- Exactly twelve bundled, hash/size-pinned assets, loaded into immutable bytes before WebKit starts; no guest ISO or disk image.
- Exact `orivyn-vm://bundle/<allowlisted-file>` routes; GET only, no credentials/query/port/percent-encoded alias. Native owner UUID is the index fragment, never an asset path.
- Per-file size cap, regular-file/O_NOFOLLOW reads, exact SHA-256 and total16 MiB asset bound. No arbitrary app file, chat, Keychain or account bridge.
- Nonpersistent WKWebsiteDataStore, no native cookies/shared browser store. CSP denies external network, workers/frames/objects/forms and permits only bundled script plus WASM evaluation. New windows/downloads/external navigation rejected.
- Current owner messages only: version1, UUID, ready/running/paused/stopped/error, bounded instruction count. No command execution or guest text output through the bridge.
- Background/memory/thermal/Stop invalidates the owner first, drops handlers/surface and requests blank-document teardown. This is NOT proof that WKWebContent process memory is synchronously reclaimed. Do not start an LLM on that assumption; physical resource handoff still needs measurement.
- A hard 60-second native proof timer requests Stop; no unattended emulator loop.
- 64 MiB guest RAM +2 MiB VGA for BIOS-only trial, not a total process memory budget. Bounded checkpoint persistence is implemented but native-unverified. No guest apps, external helper or runtime computer dependency.

## Known native questions, not hidden fallbacks
System WebKit must verify custom-scheme Fetch/HTTPURLResponse behavior, CSP `wasm-unsafe-eval`, the securityOrigin value and actual dynamic WASM execution. Failure stops with a visible error; there is no remote/CDN, arbitrary `unsafe-eval`, unrestricted file URL or alternate browser fallback. Native screenshot must show the actual BIOS, not only an event counter.

Swift policy tests cover route rejection, actual bundled hashes, corrupt/oversize/symlink/traversal refusal, immutable bytes after disk changes, and stale/malformed bridge messages. JS tests cover stop during load, ready after stop, duplicate start, input limits and NIC violation. Native nested lifecycle and physical phone acceptance are still open.

## Provenance and distribution restriction
Engine v86 0.5.473, source315b2b0b758703ef0e6cc7b4088d6068f83f3c20. `PINNED_ASSETS.json` preserves upstream provenance; `ASSET_MANIFEST.json` includes locally authored wrapper hashes. Notices retain BSD/MIT plus LGPL/GPL firmware licenses. Corresponding firmware source/configuration is retained in the sibling prototype, not copied as executable guest content here. Exact third-party release compliance remains a packaging gate; these files are internal research, not permission to publish binaries.

TinyCore ISO was deliberately NOT copied. The separate worker is constructing a maintained source-compliant guest. Only after its license and actual desktop tests pass may a native guest gate be added.

## Remaining guest acceptance
1. Explicitly reviewed guest hash/config/schema and immutable read-only root.
2. Airplane-mode actual graphical boot; type in a real editor, open its menu, create/read a guest file.
3. Bounded whole-VM checkpoint with engine+guest+configuration identity/digest and atomic storage; destroy/relaunch and freshly read the file. Nonpersistent WebKit storage here cannot satisfy this.
4. Corrupt/mismatched state, repeated Stop/start, background/thermal/low-memory, WebContent termination and stale callbacks.
5. Physical iPhone16Plus/iOS26 memory high-water mark, Stop latency, keyboard/touch, 20-minute heat/battery and resource handoff. Host/simulator success is not physical acceptance.

### Compatibility recovery

The pinned upstream loader tries `v86-fallback.wasm` when its optimized module is rejected. Upstream Makefile's optimized flags add bulk-memory, multivalue and SIMD128; the fallback uses CARGO_FLAGS_SAFE. Both assets come from the same checksum-verified npm archive, not another mirror/version. The isolated loader now restores exactly one local fallback attempt and reports bounded native-visible exception diagnostics. CSP, no-network policy, hashes,64MiB guest RAM,2MiB VGA and60-second proof limit remain unchanged. Both actual BIOS engines pass host tests; native compatibility and physical resource measurements remain unverified until new evidence.

### Restricted scheduler diagnosis (2026-11-12)

Native build `6af648bd10a05158d8122eff` at `02a672f4` exposed `engine promise: SecurityError: The operation is insecure`, followed by the bounded initialization deadline. v86's browser scheduler selects a Blob Worker whenever the Worker constructor exists, but this proof intentionally has `worker-src 'none'`. The host Node tests used a different scheduler and missed that boundary.

The isolated document now disables the Worker capability before the unmodified, checksum-pinned vendor loads, selecting its existing main-thread timer scheduler. CSP remains unchanged; no workers, network or external fallback are authorized. A browser-like VM context test with no Node process executes real BIOS instructions using that scheduler and proves no Worker is constructed. This is host evidence only. The subsequent native BIOS gate passed as recorded below; no native desktop success is claimed. Main-thread scheduling responsiveness and physical iPhone thermals remain acceptance work.

### Native scheduler verification and checkpoint work

Build `6af64b1210a05158d8122fa4` at `49e49913` passed seven native policy/delegate tests and both BIOS execution/lifecycle UI tests on the iPhone16Plus simulator. The retained screenshot visibly shows SeaBIOS and7,594,831 executed instructions. This verifies the scheduler repair in actual WKWebView, not a complete guest desktop or physical iPhone.

The subsequent checkpoint implementation is intentionally isolated in this harness. It adds owner/origin-pinned request/reply transfer,128KiB chunks,256MiB maximum, a streaming native store with atomic generation publication and reread checksums, generation-pinned restore, free-space checks and explicit cleanup policy. No automatic snapshot deletion is enabled. Saves pause the machine; restores require explicit Resume. The identity covers both WASM variants, JS engine, both BIOS ROMs and exact configuration. This harness still has **no licensed operating-system guest** and has not been integrated into the shipping app.

Local verification:26 JavaScript tests pass, including actual BIOS RAM/instruction-pointer state persisted to disk and restored into a fresh emulator;12 asset/native-manifest checks and79 Python checks pass. Eight native storage tests, five native bridge tests and a native checkpoint/relaunch UI test are authored but **not compiled or run** yet. These new source changes supersede the prior native-verified snapshot, so the complete changed harness requires a new native gate before any checkpoint success claim. No further free build minutes were spent here.

### Native checkpoint verification (2026-11-13)

Codemagic build `6af65a7210a05158d812340b`, exact private commit
`b6b5c513bb3253f4f18657d13056ae3d2c3f1463`, passed22native unit tests and3UI tests
on iPhone16Plus simulator/iOS26. The actual WKWebView BIOS checkpoint saved,
app terminated/relaunched, state restored and waited for explicit Resume.
Storage corruption/identity/generation tests and both invalidation-drain races pass.
The Codemagic run retains native logs, xcresult and screenshot evidence.
This supersedes the earlier unrun checkpoint status only: there is still no guest
in this native harness and no physical-device or complete-desktop claim.
Free build usage after verification478/500; subscription remains disabled.

### Maintained guest staging (internal, not native integration)

`materialize_guest.py ARCHIVE DESTINATION` accepts only the pinned locally supplied
`gzip -n` maintained guest archive. It checks the compressed digest before expansion,
streams within the exact 135266304-byte bound, checks the resulting disk digest,
then atomically replaces the destination. Corrupt inputs leave existing data intact;
leaf symlinks and oversized archives are rejected. This helper never downloads assets
or runs in the app. Supply a trusted local output directory. Publication/source-license
approval and native full-guest acceptance remain separate gates.

The exact maintained archive was expanded locally and its disk hash matched
`0897e5f867267c209f2866e2ee960971caf25886eb0345fe2f514b11e19cf0f1`.
Three materializer tests passed; the existing26JS tests and12asset checks also passed.
No Codemagic run or public release was triggered for this staging change.
