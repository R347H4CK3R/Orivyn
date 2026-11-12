# Orivyn 1.0.0 release plan and acceptance ledger

Owner directive dated 2026-11-12: application Orivyn, assistant Jarvis, target 1.0.0; original branding; genuinely usable, independently tested native iPhone assistant, not proprietary service parity. Continue ordinary authorized engineering, preserve private source and free builds, stage every verified update in Strata before activation. Never label attempted or missing capability complete.

## Current checkpoint

- Public verified development preview: 0.1.0 build 4 in Orivyn-Distribution and Strata. Public IPA SHA `196091d0989f39a01787491efcfb7d1461bbca3a2f9d26f4d82b5bc7fa12ee7d`; app identity `app.jarvisevo.ios` preserved.
- Strata commit `e2305dc5c145dd1f42b386529d01fe6224057734`: 15 entries, prior 14 unchanged. Anonymous binary verification plus all five public catalog files byte-checked. Standalone distribution metadata commit `e9fba9feec430788610d13d354c830d20a8ac966` points to the same verified release asset.
- Private integration checkpoint `c71b3e393bc35a622671689c1d3a9f5f781bb823`: real native tool source, 64 Python checks pass; native build `6af5f7769679c85ac0af2e4e` failed three main-actor legacy UI delegate conformances before tests. Narrow @preconcurrency fix committed in the subsequent candidate; recompile required.
- Earlier focused native run `6af5f2259679c85ac0af2bf4` on `df689ccddaad825c62dda74427e6c845494cd9a7`: 47 unit tests pass; actual OS reminder schedule/relaunch/cancel and cancel-form UI pass. Four new native tool controls had genuine RED. Three incoming-link assertions failed because XCUIApplication.open launched a new process; test-only warm routing now uses documented XCUISystem.open, still awaiting rerun.
- Automatic routing and Desk acceptance tests are authored before production. Pure router/suggestion/Desk lifecycle tests are deliberately excluded from absent-feature UI snapshots until types exist.

## Workstreams and honest completion state

| Workstream | Existing verified baseline | Remaining 1.0.0 work/gate |
|---|---|---|
| Chat and history | Streaming, conversations, search, management, actions, rendering baseline tested | Regress full final source; actual new screenshots |
| Offline inference | Real default-model download/answer/relaunch; 9 full pinned weight CPU smoke tests | Automatic selection/download/switch ownership; real general/coder switching; device memory/thermal limits |
| Online inference | Configurable OpenAI-compatible implementation and automated protocol tests | User-configured real endpoint acceptance without unapproved credential/transcript disclosure; explicit remote fallback policy |
| Documents and images | Text/PDF and OCR extraction, attachment ownership tests | Multimodal image understanding/generation require compatible real provider/runtime; do not call OCR vision |
| Voice | Native speech/audio state-machine and integration baseline tests | Final regression plus physical microphone/speech/background interruptions |
| Memory and context | Persistence, bounded prompts, shared runtime | Final context/router regression; measured performance limits |
| Native tools | OS reminder lifecycle passed; Mail/Calendar/Safari/Location source written | Native SDK retest, actual system controller/cancel/location capture; physical provider delivery/GPS limits |
| Automatic models | Design + real UI RED tests prepared | Pure router, network policy, owner-tagged async preparation, progress/cancel, no premature history; real runtime switching |
| Agent/plugins/computer | Research and protocol architecture only | Reviewed plugin manifests, real connection/authentication, schema/permission broker, bounded tasks/logs/resume, actual backend test; no simulated computer |
| Orivyn Desk | Apple API research + disconnected-state test | External scene controller, app-owned panels/layout/input, privacy lifecycle, physical display attach/reconnect/resolution testing |
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

Run the combined native gate: corrected actual system tools and incoming links, plus missing Automatic/Desk UI controls. Use genuine RED to unblock isolated pure-router and external-workspace implementation. In parallel, prepare the permissioned plugin/agent protocol design and final-source regression coverage. Log precise commits, checks, errors, repairs and unresolved device/provider requirements at each checkpoint.
