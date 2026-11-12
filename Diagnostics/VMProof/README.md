# Orivyn native BIOS-only proof

**Isolated internal prototype. Native compilation and WKWebView execution have NOT run. Not a virtual desktop release.** No main-app files, remote commits, CI launch, IPA or publication were performed.

`./verify.sh`: five owner/lifecycle/input policy tests plus an actual pinned v86 BIOS execution test. Tests first failed on the missing controller, then passed. The real host test uses the bundled engine, WASM and ROMs, executes >100,000 guest instructions, and verifies there is no emulated NIC/relay. `BIOS_HOST_RESULT.json` records the actual instruction count and host memory; it is not iPhone evidence.

`materialize_assets.py` can recover the four exact engine/ROM assets from the pinned official npm archive and exact GitHub source commit during development. It rejects redirects, oversized responses, package/hash changes and nonregular archive members. It is not included as app executable code or called at runtime. The four generated assets are git-ignored; do not upload compiled blobs merely to run this proof.

`run_native.sh` is a prepared XcodeGen/iOS 26 Swift 6 native test command. It runs five Swift policy tests and two actual UI tests: system-WebKit BIOS/WASM execution with retained screenshot, explicit Stop, and background without automatic restart. No fixture CPU output or screenshot is injected. It remains unexecuted here because no Xcode/Swift Apple SDK is available. The parent owns the free CI budget and must launch it explicitly.

## Boundary
- Exactly eight bundled, hash/size-pinned assets, loaded into immutable bytes before WebKit starts; no guest ISO or disk image.
- Exact `orivyn-vm://bundle/<allowlisted-file>` routes; GET only, no credentials/query/port/percent-encoded alias. Native owner UUID is the index fragment, never an asset path.
- Per-file size cap, regular-file/O_NOFOLLOW reads, exact SHA-256 and total16 MiB asset bound. No arbitrary app file, chat, Keychain or account bridge.
- Nonpersistent WKWebsiteDataStore, no native cookies/shared browser store. CSP denies external network, workers/frames/objects/forms and permits only bundled script plus WASM evaluation. New windows/downloads/external navigation rejected.
- Current owner messages only: version1, UUID, ready/running/stopped/error, bounded instruction count. No command execution or guest text output through the bridge.
- Background/memory/thermal/Stop invalidates the owner first, drops handlers/surface and requests blank-document teardown. This is NOT proof that WKWebContent process memory is synchronously reclaimed. Do not start an LLM on that assumption; physical resource handoff still needs measurement.
- A hard 60-second native proof timer requests Stop; no unattended emulator loop.
- 64 MiB guest RAM +2 MiB VGA for BIOS-only trial, not a total process memory budget. No snapshot import/persistence, guest apps, external helper or runtime computer dependency.

## Known native questions, not hidden fallbacks
System WebKit must verify custom-scheme Fetch/HTTPURLResponse behavior, CSP `wasm-unsafe-eval`, the securityOrigin value and actual dynamic WASM execution. Failure stops with a visible error; there is no remote/CDN, arbitrary `unsafe-eval`, unrestricted file URL or alternate browser fallback. Native screenshot must show the actual BIOS, not only an event counter.

Swift policy tests cover route rejection, actual bundled hashes, corrupt/oversize/symlink/traversal refusal, immutable bytes after disk changes, and stale/malformed bridge messages. JS tests cover stop during load, ready after stop, duplicate start, input limits and NIC violation. Native nested lifecycle and physical phone acceptance are still open.

## Provenance and distribution restriction
Engine v86 0.5.473, source315b2b0b758703ef0e6cc7b4088d6068f83f3c20. `PINNED_ASSETS.json` preserves upstream provenance; `ASSET_MANIFEST.json` includes locally authored wrapper hashes. Notices retain BSD/MIT plus LGPL/GPL firmware licenses. Corresponding firmware source/configuration is retained in the sibling prototype, not copied as executable guest content here. Exact third-party release compliance remains a packaging gate; these files are internal research, not permission to publish binaries.

TinyCore ISO was deliberately NOT copied. The separate worker is constructing a maintained source-compliant guest. Only after its license and actual desktop tests pass may a native guest gate be added.

## Later guest acceptance (not implemented)
1. Explicitly reviewed guest hash/config/schema and immutable read-only root.
2. Airplane-mode actual graphical boot; type in a real editor, open its menu, create/read a guest file.
3. Bounded whole-VM checkpoint with engine+guest+configuration identity/digest and atomic storage; destroy/relaunch and freshly read the file. Nonpersistent WebKit storage here cannot satisfy this.
4. Corrupt/mismatched state, repeated Stop/start, background/thermal/low-memory, WebContent termination and stale callbacks.
5. Physical iPhone16Plus/iOS26 memory high-water mark, Stop latency, keyboard/touch, 20-minute heat/battery and resource handoff. Host/simulator success is not physical acceptance.
