# Orivyn

A native, independent iPhone assistant for iOS 26+. **Orivyn is the app; Jarvis is its assistant.** The target release is **1.0.0**, currently in development, not yet release-ready. Original branding, local-first inference and no paid tiers for core offline use. Not an OpenAI product or a reproduction of proprietary GPT services.

## Install the verified preview

- [Shared Strata source](https://raw.githubusercontent.com/R347H4CK3R/OmniForge/main/unified-source.json)
- [Orivyn-only source](https://raw.githubusercontent.com/R347H4CK3R/Orivyn-Distribution/main/source.json)
- [Verified build 4 binary and installation notes](https://github.com/R347H4CK3R/Orivyn-Distribution/releases/tag/orivyn-v0.1.0-build4)

Add either source in SideStore. Both identify the same app. Distribution is public; this source repository remains private. Jarvis Preview/GhostAI is a separate app and is unchanged. Unsigned ARM64 packages require signing for the user's device; free-signing limits and refresh still apply.

Current public version: **0.1.0, build 4**, iOS 26+, 4,192,466 bytes, SHA-256 `196091d0989f39a01787491efcfb7d1461bbca3a2f9d26f4d82b5bc7fa12ee7d`. This distribution copy adds only the llama.cpp MIT notice to the original tested payload; every original entry remains byte-identical. Models are downloaded separately. No credentials, source code or personal conversations are included.

## Verified baseline and active work

Build 4's exact original source `791dc4755a0ab1039d3fd628a9480d1d4419d182` passed 62 Python, 288 native and 27 UI tests, including actual default-model download, inference and relaunch. It includes chat, history, documents/OCR, voice infrastructure, memory, projects, a reconstructed video-inspired workspace and nine publisher-pinned downloadable models. [Evidence and limits](docs/ORIVYN_RECONSTRUCTION_QA.md).

The private integrated candidate is **0.1.1 build 5**, not release-ready. CircleCI pipeline 18 tested exact source `cf3bac525aa24113302b2747ca33bb6ab33aa59e`: 816 unit tests executed, **1 skipped**, zero failures; **50 UI** tests, zero failures; native build and unsigned ARM64 packaging succeeded. The preserved evidence is a rendered console excerpt and package provenance, not the complete xcresult. It includes a real phone-contained guest in Simulator, guest file/checkpoint persistence across app relaunch, and usable terminal/taskbar rendering. It does not establish physical iPhone, HDMI, SideStore or thermal acceptance.

A read-only source audit at `ad0a63d94c609c9639baa8210945e95060d566a8` confirms chat/history, local models, automatic routing, memory, attachment extraction, native tool review screens, permissioned MCP, Image Playground integration, phone-contained desktop and pinned read-only repository inspection are present. Changes after the pipeline-18 checkpoint have **not been native-tested** together. Source presence and portable regression results are not final acceptance. General reliable autonomous tool planning, visual image understanding, automatic cross-device synchronization and self-applied repository repair remain unfinished.
[1.0.0 scope, gates and honest status](docs/ORIVYN_1_0_RELEASE_PLAN.md) is the current release checklist. Test candidates retain development version metadata until the final release gate is satisfied.

## Architecture and boundaries

- SwiftUI/UIKit, SQLite history, local attachment extraction, editable saved memory.
- A single shared llama.cpp runtime, verified GGUF installs and bounded context. [Catalog, licenses, memory guidance and full-weight smoke evidence](docs/model-catalog/README.md).
- Optional configured remote endpoints are off by default and can charge separately. Only enabling an endpoint authorizes its use; local-first does not mean hosted services are universally free.
- Native system editors retain explicit Send/Add/review. iOS sandbox, entitlement, background and memory restrictions still apply to sideloaded apps.
- Images currently provide OCR text, not general visual understanding. Image Playground has an explicit iOS 26-only on-device capability gate; actual physical-device generation remains unverified. General visual understanding, dependable general autonomous tool orchestration and automatic cross-device sync remain unfinished. A phone-contained emulator is integrated and has Simulator guest/checkpoint evidence; physical iPhone usability and external-display acceptance remain unverified. No external computer companion is required or deployed.
- Compatible external displays can host Orivyn-owned panels. iOS does not let Orivyn embed arbitrary installed apps or become a system-wide desktop OS.

The owner's recording confirms navigation on a physical iPhone and an installed-model indicator. It does not establish the exact package hash, a fresh SideStore install/refresh, offline/voice behavior, large-model thermal stability or HDMI acceptance. Automated and physical tests are reported separately.

## Development and provenance

Current development instruction: complete all work possible without macOS and skip Mac-runner verification. Keep Apple SDK, simulator, physical-device and release acceptance explicitly unverified for new source; portable success does not satisfy those gates.

Run the local aggregate with an installed Swift 6 toolchain and Node:

```sh
python3 scripts/run_portable_checks.py --swift /path/to/swift --output /path/outside/checkout/new-evidence
```

This runs Python contracts, model-catalog validation, JavaScript agent/VM tests and exact Foundation production/tests. It preserves per-stage logs, a source SHA-256 manifest and `SUMMARY.json`, continues independent stages after a failure and returns a failing exit code if any stage fails. Use a new output directory each time. Add `--sqlite-source /path/to/sqlite-amalgamation` to include SQLite persistence tests; otherwise that stage is explicitly skipped. No dependency downloads, CI dispatch, model/service calls or publication occur. Existing tokenizer and Linux redirect-fixture exclusions are disclosed in the summary and logs.

Native tests and ARM64 packaging require Xcode 26 on macOS and remain outside this portable command. The existing native workflow is preserved for later authorized use: `scripts/ci_macos.sh`, wrapped by `scripts/run_native_tests.sh`. Do not enable billing or infer native success from portable checks.

This workspace was reconstructed from independently recovered baseline `f4ac85877bfa707061a3c6cd902412be65cff34e`; lost candidate commits were not recovered byte-for-byte. Preserve original bundle/storage/Keychain identities and historical branches. [Reconstruction](docs/ORIVYN_WORKSPACE_RECONSTRUCTION.md), [video evidence](docs/VIDEO_REFERENCE.md), [historical documentation](docs/HISTORICAL_BASELINE_README.md).

