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

The development branch adds incoming text review, local reminders and real native Mail/Calendar/Safari/one-shot location tools. These are not in public build 4. A focused run passed 47 native unit tests and actual OS reminder create/relaunch/cancel UI; incoming URL test harness and three legacy SDK delegate conformances were corrected, with the next native gate pending. Automatic model routing, permissioned plugin/tool workflows and Orivyn Desk are being implemented under separate test-first plans. Do not interpret source presence or compilation as completed acceptance.

[1.0.0 scope, gates and honest status](docs/ORIVYN_1_0_RELEASE_PLAN.md) is the current release checklist. Test candidates retain development version metadata until the final release gate is satisfied.

## Architecture and boundaries

- SwiftUI/UIKit, SQLite history, local attachment extraction, editable saved memory.
- A single shared llama.cpp runtime, verified GGUF installs and bounded context. [Catalog, licenses, memory guidance and full-weight smoke evidence](docs/model-catalog/README.md).
- Optional configured remote endpoints are off by default and can charge separately. Only enabling an endpoint authorizes its use; local-first does not mean hosted services are universally free.
- Native system editors retain explicit Send/Add/review. iOS sandbox, entitlement, background and memory restrictions still apply to sideloaded apps.
- Images currently provide OCR text, not general visual understanding. Hosted image generation, autonomous backend tools, cross-device sync and remote computers require real implementations/configuration and verification; none are represented as connected merely by displaying a page.
- Compatible external displays can host Orivyn-owned panels. iOS does not let Orivyn embed arbitrary installed apps or become a system-wide desktop OS.

The owner's recording confirms navigation on a physical iPhone and an installed-model indicator. It does not establish the exact package hash, a fresh SideStore install/refresh, offline/voice behavior, large-model thermal stability or HDMI acceptance. Automated and physical tests are reported separately.

## Development and provenance

Use the existing manual Codemagic workflows and remaining free capacity; do not enable billing. Local source/package checks: `python3 -m unittest discover -s scripts/tests -p 'test_*.py'`, `python3 scripts/model_catalog.py --check`. Native tests and ARM64 packaging require Xcode 26 on macOS. Full workflow: `scripts/ci_macos.sh`, wrapped by `scripts/run_native_tests.sh` to preserve failures and artifacts.

This workspace was reconstructed from independently recovered baseline `f4ac85877bfa707061a3c6cd902412be65cff34e`; lost candidate commits were not recovered byte-for-byte. Preserve original bundle/storage/Keychain identities and historical branches. [Reconstruction](docs/ORIVYN_WORKSPACE_RECONSTRUCTION.md), [video evidence](docs/VIDEO_REFERENCE.md), [historical documentation](docs/HISTORICAL_BASELINE_README.md).
