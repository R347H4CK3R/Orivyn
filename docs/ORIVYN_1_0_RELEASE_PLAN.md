# Orivyn 1.0.0 release plan and acceptance ledger

## Current recovery and acceptance status (supersedes historical checkpoints below)

Latest change: local agent search includes stored attachment names/text with bounded labeled evidence. Two exact production-branch tests and unchanged Swift output through the verified-plan reducer pass. It does not read original files or verify OCR facts.

Previous change: endpoint credentials now use explicit keep/replace/remove intent, exact UTF-8 binding, no saved-secret form preload and cleared temporary drafts. Eight core and eight extracted-method host checks pass. Native Keychain/UI lifecycle still require testing.

Previous change: conversation sharing now accurately labels System/Jarvis/You, incomplete responses and attachment exclusions; five new regression tests pass. Native share-sheet behavior remains unverified.

The latest selected private source checkpoint is `dc17fc1c769133d95a6365c25c2b8afe71c873e7`. It is not a complete build-ready checkout and must not be treated as the final release. The canonical candidate remains 0.1.1 build 5; the existing published preview remains 0.1.0 build 4. No 1.0.0 IPA has been produced from this source.

Current portable evidence: 341 Foundation XCTest cases, 142 Python tests, 76 agent tests, 39 VM tests. The exact offline engine/SQLite integration has passed nine checks with each of cached Qwen2.5-0.5B and 1.5B, including five whole-answer assertions. These are bounded host proofs, not Apple SDK type checking or iPhone acceptance. Failed smaller-model tool decisions and catalog instruction cases remain failures, not waived.

Native capacity is blocked: the last account check found Codemagic at 496/500 free minutes and private GitHub compute/storage exhausted. Do not enable billing, make source public, or launch an inadequate four-minute native job. Earlier capacity figures below are historical.

### Build-ready recovery steps

1. Preserve the canonical candidate and `BUILD_RECOVERY_MANIFEST.json`: the current regular build-input files and exact sizes listed in that inventory. Verify every listed SHA-256 after transfer to an authorized private Mac workspace. This inventory is not itself a backup; do not delete the canonical copy. The selected GitHub checkpoint alone lacks required build assets. Do not overlay it onto an arbitrary old checkout and assume parity.
2. Preserve the pinned compressed guest `Fixtures/maintained.img.gz`, VM JavaScript/WASM/BIOS resources and their license/source provenance. The generated 135,266,304-byte guest disk is excluded from the transfer inventory because `scripts/materialize_guest.py` reconstructs it from the pinned compressed fixture. Do not substitute the older unsupported guest.
3. On a Mac with Xcode 26+, iOS 26 simulator and sufficient authorized free build time, provide Python, Node and XcodeGen. `scripts/bootstrap_llama.sh` validates official llama.cpp b9049 XCFramework SHA-256 `49c374bf78d98f53bfb3571b2285d315351ca6a5c1112191ae6f8b2616dec1d1`. A validated existing archive can be supplied via `LLAMA_ARCHIVE`; never bypass checksum or device/simulator slice checks. Generated frameworks and `.cache` are not in the inventory.
4. Run `bash scripts/ci_macos.sh` from the restored candidate. It materializes the guest, runs portable checks, prepares the pinned native dependency/test model, generates Xcode project, runs the full native test target with real inference required, builds unsigned ARM64 and verifies the IPA structure. It does not publish. Repair every actual compilation or runtime failure and rerun; a focused gate alone is not the full release gate.
5. Inspect `.xcresult`, recordings/screenshots, all test failures/skips and verified IPA metadata. Do not raise the version merely because compilation succeeds. Simulator tests still cannot verify physical file protection, thermals, microphone/audio routing, actual image generation or HDMI behavior.
6. Install through SideStore on the user's iPhone 16 Plus for physical acceptance: offline model download/select/generation/relaunch, attachments and memory, microphone interruption/denial, location permission/approximate mode, reminder delivery, background cancellation/recovery, storage pressure, external-display privacy/reconnect and actual phone-contained guest usability. Preserve evidence and explicitly record unsupported capabilities.
7. Resolve remaining product gaps before 1.0.0: dependable general autonomous tool use, broad image understanding quality, automatic cross-device sync, and self-applied source repair are not proved by existing deterministic tools/OCR/manual backup/read-only repository inspection. Obtain real configured-provider/plugin results only within authorized accounts; never substitute parser tests for service execution.
8. Only after acceptance passes, set 1.0.0 consistently, rebuild and verify the final exact artifact. Stage its valid hosted IPA URL, size/hash and version in Strata, validate the source entry, then activate distribution according to the user's catalog-first requirement. Retain the prior working preview for rollback. No release/cross-device-install claim before verification.


Owner directive dated 2026-11-12: application Orivyn, assistant Jarvis, target 1.0.0; original branding; genuinely usable, independently tested native iPhone assistant, not proprietary service parity. Continue ordinary authorized engineering, preserve private source and free builds, stage every verified update in Strata before activation. Never label attempted or missing capability complete.

## Current checkpoint

- Public verified development preview remains **0.1.0 build 4** in Orivyn-Distribution and Strata. Public IPA SHA `196091d0989f39a01787491efcfb7d1461bbca3a2f9d26f4d82b5bc7fa12ee7d`; identity `app.jarvisevo.ios` preserved. No 1.0.0 or new IPA has been published.
- Latest privately backed-up, native-tested source: `730ec2f2e9ced5b8983245956464545eb18cfe76`, tree `dc94a509ddb8a9d16189be66abce4d67b5088a1c`. Focused run `6af6257710a05158d81222a1` passed **90 unit tests and three UI tests**; **one physical-device-only file-protection test was explicitly skipped**, not passed. Real active-engine release → reload/inference and image-form exclusive ownership passed.
- Prior run `6af61e6a10a05158d8121fe4` passed 154 of 155 units and all four UI tests, including real general → 1.5B coder → relaunch → general inference and background credential clearing. The sole Simulator protection mismatch is now correctly separated from physical acceptance. All 41 MCP tests passed; no actual external server/account was contacted.
- Native tools baseline: 78 selected units and nine real UI flows passed for Mail/Calendar/Safari/location/reminder/incoming-link controls. Physical account delivery/GPS/HDMI/voice/image generation remain distinct unverified gates.
- Fresh local aggregate: 70 Python tests, catalog generator check, shell syntax and whitespace pass. Full final-source aggregate native test/package remains pending.
- Free build capacity refreshed after the resource gate: **421/500 minutes used, 79 remaining**, subscription disabled and no previous transactions. Combine essential gates; do not enable paid billing.
- Phone-only vision and actual desktop are isolated research, not production features. Actual 500M VLM pixel inference works but blank-image hallucinations block broad quality claims. A larger official Apache-2.0 model is under bounded comparison. Native ImageIO/mtmd and WKWebView BIOS harnesses are being prepared for one combined gate.
- The old TinyCore graphical guest is excluded from packaging because exact source/license coverage is incomplete. A signed, pinned maintained Buildroot guest is compiling locally with two jobs; an execution-session interruption was verified and resumed incrementally with a filesystem lock. No guest build completion or iPhone desktop claim is made.

## Workstreams and honest completion state

| Workstream | Existing verified baseline | Remaining 1.0.0 work/gate |
|---|---|---|
| Chat and history | Streaming, conversations, search, management, actions, rendering baseline tested | Regress full final source; actual new screenshots |
| Offline inference | Real default-model download/answer/relaunch; 9 pinned weight CPU smoke tests; real automatic general/coder/relaunch/switch passed | Final full-source regression; physical memory/thermal/battery limits |
| Online inference | Configurable OpenAI-compatible implementation and automated protocol tests | User-configured real endpoint acceptance without unapproved credential/transcript disclosure; explicit remote fallback policy |
| Documents and images | Text/PDF and OCR extraction, attachment ownership tests | Multimodal image understanding/generation require compatible real provider/runtime; do not call OCR vision |
| Voice | Native speech/audio state-machine and integration baseline tests | Final regression plus physical microphone/speech/background interruptions |
| Memory and context | Persistence, bounded prompts, shared runtime | Final context/router regression; measured performance limits |
| Native tools | Native OS reminder lifecycle, Mail fallback, EventKit editor/cancel, Safari return and simulated location/clear passed | Physical provider delivery/GPS and final full-source regression |
| Automatic models | 25 router tests, owner/network regressions, opt-in UI and real 1.5B useful code/download/switch/relaunch pass | Physical resource acceptance; explicit policy for optional online routing |
| Agent/plugins/virtual desktop | 41 MCP tests, broker/log/review and background privacy pass; explicit connection UI | Actual authorized service test, bounded autonomous orchestration; genuine phone-only guest/native lifecycle/physical acceptance, not a remote companion |
| Orivyn Desk | App-owned scene/controller, consent reducer and phone scrolling controls pass focused simulation | Physical attach/reconnect/lock/resolution; no arbitrary installed apps or whole desktop claim |
| Synchronization | Local data only | Select supported secure sync mechanism, conflict/privacy tests and actual supported-device verification |
| Branding/distribution | Original Orivyn SVG/icon, app labels, private repo rename, public binary-only feed | Jarvis assistant identity, current README/screenshots, final 1.0.0 metadata only at release gate |

## Release acceptance gates

- [ ] Full exact-source compilation, aggregate unit/integration/UI checks pass; no hidden skips.
- [ ] Actual ARM64 IPA produced and independently inspected (identity, version, minimum OS, Mach-O, resources, licenses, privacy and excluded fixtures/secrets).
- [ ] Core chat, offline local response, persistence, conversation management, supported voice/attachments/memory verified on final source.
- [ ] Configured online inference verified with explicit authorized provider and disclosure scope; no free-hosted-service claim.
- [ ] Requested new supported features have real execution evidence and failure/cancel/interruption coverage, not merely controls or stubs.
- [ ] README, screenshots, release notes and catalog represent the implemented build, including platform/provider limits.
- [ ] Native simulation versus physical iPhone install/refresh/voice/offline/thermal/HDMI evidence distinguished. Missing hardware is a named blocker, not a fabricated pass.
- [ ] Final catalog staged and validated before public asset activation; anonymous full binary hash/structure check before live feed update. Preserve old verified entry if any check fails.
- [ ] 1.0.0 marked ready only after the required gates above. Until then, source/test candidates and incomplete scope are labeled as such.

## Next objective

Complete the isolated native vision/runtime and BIOS/WKWebView gates within the remaining free budget, resolve measured vision quality and guest redistribution issues, then integrate verified functionality into the existing exclusive resource owner. Continue the requested bounded autonomous workflow and synchronization work without relying on an external computer. The companion stays stopped and excluded. Physical iPhone/HDMI, supported real provider delivery, full desktop interaction and final exact-source package/catalog gates remain explicit.

Earlier checkpoints below are chronological evidence, not current-status claims. Later corrections supersede earlier hypotheses.

## 2026-11-12 native checkpoint and next candidate

Run `6af5fb7d9679c85ac0af2fef` on `8f61fdd4e00b5b51264c706b03d786da364540ef` compiled the legacy UIKit delegate bridges and passed all 78 selected native unit tests plus nine individual native UI tests. Real Safari open/return, EventKit editor/cancel, simulated one-shot location/clear, editable Mail fallback, OS reminder schedule/relaunch/cancel, and warm incoming-text review/cancel/first-request ownership passed. Mail delivery, real calendar account persistence, physical GPS, Shortcuts app registration and hardware remain separate unverified gates. The combined workflow intentionally failed because two Automatic controls and Desk entry were absent; those exact failures preceded implementation.

The next source candidate implements bounded local automatic routing, owner-checked preparation, URLSession network policy, progress/cancel, native review suggestions, and an app-owned external-display privacy controller/read-only panel. It includes 20 router, 11 suggestion, 15 coordinator, three network configuration and eight Desk state tests, all awaiting native execution. The standalone plugin UI acceptance remains intentionally RED before MCP production. No native-pass claim applies to this new source yet, and no new IPA is released.

Desk first scope is not the full requested desktop: resizable windows, file manager, terminal, external keyboard/pointer interaction and real remote computer require additional work and tests. No simulated remote machine or embedded arbitrary iOS apps is claimed.


Run `6af601b89679c85ac0af3217` on `b826d5a7e19c5f02560646db5cbd7501ca9ee0dd` completed: all 135 selected unit tests and 11 individual UI tests passed, including the native suggestion and disconnected Desk controls. Two UI tests failed. PluginConnectionUITests:18 established genuine missing `plugin.add` RED before MCP implementation. AutomaticModelUITests:20 failed to reveal cellular choice because XCTest tapped the full-row parent Switch center (x215), whereas the nested real UISwitch occupied x329–392; the failure hierarchy shows both remained value0. The test now targets the actual nested knob and asserts value1, preserving all persistence/network assertions. This is not yet a verified repair until native rerun.

Follow-up source adds privacy-gated phone scrolling for the noninteractive display, a real two-download/general→coder→relaunch→general inference gate, and a more useful but honest Jarvis system instruction. Source-contract RED then GREEN was observed for actionable-help wording and final-candidate CI location/deadline requirements. Full local aggregate now 68 tests. New native compilation, real download/switch performance, screenshot review and final package remain pending.


## Real automatic quality checkpoint
Run `6af60c119679c85ac0af3616` on `1eb8e787ae305183ffaf6de8eb3bdb8e11ba5b54`: 22 selected unit tests and three UI tests passed. The actual nested UISwitch repair is now verified; opt-in/cellular-off persistence and Desk disconnected controls pass. The general 0.5B download and genuine Paris answer passed. Coder 0.5B failed the useful Python-output assertion; the native recording shows bare arithmetic, not the requested printing statement. No quality assertion was weakened.

Bounded Linux CPU comparisons with the actual system prompt reproduce the 0.5B failure under temperature 0.7 and greedy; shorter system prompts do not fix it. The existing official 1.5B coder returned `print(2 + 2)` in three seeded sampling runs and greedy. This is narrow task evidence, not a broad model-quality or physical-iPhone benchmark. Automatic now targets that stronger model within explicit RAM/storage/download safeguards. Native 1.5B download/switch/relaunch remains pending.

## Permissioned plugin candidate checkpoint
Private `00e9a9ef35868ee83cfa681e27a6a04bda70920e` contains the bounded MCP transport, native connection/install/review/call forms, separate explicit Keychain storage, and durable outcome log. Native run `6af6103f9679c85ac0af37bc` is the first gate for 41 MCP plus 25 broker/journal/review cases and two UI cases. Review regression tests intentionally precede repairs for pre-canceled dispatch, form-token retention on background, and failed outcome persistence. Source presence is not a passing gate. No real external account/server or virtual desktop has been connected; no remote result is treated as independently verified execution.


### First MCP native findings
Run `6af6103f9679c85ac0af37bc` compiled the actual production client and passed all 36 MCPClientTests, 12 review/journal tests and 10 of 13 broker tests. Three broker regressions failed as intended: pre-canceled connect/run still dispatched, and failed outcome persistence left Running and allowed more calls. These now have narrow fixes, pending native recheck. Five separately named MCPURLSessionTransportTests were accidentally omitted from that selector and are explicitly included next; no claim of 41 passing cases is made.

Two plugin UI tests failed earlier than the background-token assertion. The actual app logs show repeated concurrent presentation attempts from the Section; a field briefly existed then disappeared. One stable presentation owner is now on the enclosing integration List, with all original assertions retained. The credential-background behavior remains to be exercised after this presentation fix; it is not passed.

## November 12 native correction checkpoint and phone-only scope

The owner now requires all computation in the iPhone app, without another computer. The local companion experiment is excluded from this candidate and is not deployed. App-owned Desk remains separate from the requested actual virtual desktop. An isolated, license-audited phone-contained emulator proof is being investigated; it is not yet integrated, physically benchmarked or release-ready. Existing optional endpoint connections are never automatic prerequisites for local features.

Exact private source `ead1ba759e198258c27221a1da3e633d845be528` ran native gate `6af613379679c85ac0af38fa`:
- 91 selected unit tests passed, including 25 routing, 41 MCP contract/real URLSession adapter, 13 broker and 12 execution/journal tests.
- Plugin empty setup/cancel with composer preservation passed.
- Plugin background test genuinely exposed retained form credentials. The subsequent source cancels/clears the form on nonactive phase; its native rerun is pending.
- Image creation failed on the missing entry as intended before implementation. Native Image Playground staging and library persistence are now source candidates, not verified generation.
- Actual 1.5B coder screenshot shows `print(2 + 2)`. The test's response extraction returned only `python`, the code-language label. The quality assertion remains intact; a contained accessibility group and text-view extraction repair need native re-execution. The earlier 0.5B output failure was genuine, and the stronger automatic coding floor remains.

Physical iPhone image generation, HDMI/lock/reconnect, memory/thermal behavior, real service connections, and the requested actual virtual desktop remain open acceptance gates. No new IPA or 1.0.0 release is implied by this checkpoint.


## Image, privacy and automatic-switch native checkpoint

Exact private source `167655c5dc2aa4b2ff91c56573513c8628519020`, native run `6af61e6a10a05158d8121fe4`, completed November 12 at 20:23 UTC. 154 of 155 selected unit tests and all four selected UI tests passed. All nine accepted-image persistence/import/race tests passed; no provider was involved in that persistence boundary. All 41 MCP tests and the selected broker/routing/composer suites passed.

The real two-download general → Qwen Coder 1.5B → relaunch → general switch passed, including useful `print(2 + 2)` output and Paris after relaunch. Screenshots independently confirm actual readable responses, not fixture output. Background credential clearing and plugin setup/cancel now pass. Image creation/cancel preserved the draft; the simulator truthfully reported unavailable capability. It did not create an image, so physical Apple Image Playground generation remains unverified.

The sole unit failure was initially attributed to an invalid cast of `.protectionKey` to `FileProtectionType`; a later native rerun also returned raw nil, establishing the separate Simulator limitation described below. The assertion now compares that string to `.complete.rawValue`, without skipping simulator protection or altering production storage. Its next native execution is combined with a resource-release gate. The shared engine currently retains its model after text generation, and its old unload method can return while busy, so exclusive heavy-feature ownership must be implemented before claiming final image/VM/vision memory safety.

Latest free-budget UI check: 411 of 500 macOS minutes used, 89 remaining, subscription disabled. Source candidate `fb81c072480c32642e48ccb753d6c24805f995ec` is backed up privately and starts a 15-minute-capped focused RED gate for actual model release and missing image resource ownership. No new IPA or catalog activation.

Isolated v86 proof now boots a genuine TinyCore graphical desktop, types into its editor, opens its File menu and restores a guest file from a snapshot. This is Linux component evidence only. The old TinyCore ISO has unresolved exact corresponding-source coverage for several graphical extensions and is excluded from any app package. A pinned maintained Buildroot guest is being prepared instead. Native WKWebView and physical iPhone VM acceptance remain open.


### Resource RED and physical data-protection distinction
Native `6af6229310a05158d8122162` on `fb81c072480c32642e48ccb753d6c24805f995ec` executed the real model regression and failed with `unload() returned before the active engine was reusable: busy`. Image ownership UI failed at the missing `image.creation.resources.ready` control. These failures precede the shared-release barrier and exclusive image-form lease implementation.

The corrected protection cast still returned raw nil in Simulator. Apple DTS independently reproduces exactly this `.completeFileProtection` limitation: https://developer.apple.com/forums/thread/780632 . Production protection is unchanged. The test is split into a real backup/byte/permissions test, an explicit physical-device-only metadata test (reported as skipped in Simulator), and a source-contract check retaining the complete-protection write request. None of these proves lock-time enforcement. Actual iPhone file attributes and locked-device access remain mandatory physical acceptance, not a simulator pass.


### Resource ownership native GREEN
Exact source `730ec2f2e9ced5b8983245956464545eb18cfe76` (local tree `dc94a509ddb8a9d16189be66abce4d67b5088a1c`) passed `6af6257710a05158d81222a1` at 20:50 UTC: 90 selected unit tests passed, one explicitly physical-only Complete-protection test skipped, and all three image/resource UI tests passed. The real model active-stream unload → release → reload/inference regression passed in 14.105 seconds. All 11 ownership, 32 voice bridge, 15 automatic preparation, 12 AppModel and nine accepted-image tests passed, plus ten simulator-supported staging tests. UI cancel and background dismissal preserve the composer and do not reopen the form. Actual nested Image Playground generation on hardware, physical lock protection and OS memory/thermal reclaim remain unverified; no new IPA is implied.
