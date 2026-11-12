# Orivyn reconstructed candidate

**Verified unsigned development candidate, build 4.** This candidate restores the video-inspired workspace and nine free model downloads over the independently recovered source `f4ac85877bfa707061a3c6cd902412be65cff34e`. The lost Orivyn commits were not recovered byte-for-byte. The original app identity and historical branches are preserved.

- [Workspace, reconstruction provenance and limits](docs/ORIVYN_WORKSPACE_RECONSTRUCTION.md)
- [Free model catalog, licenses, integrity and memory guidance](docs/model-catalog/README.md)
- [Owner recording inventory](docs/VIDEO_REFERENCE.md) and [suggestion flow](docs/SUGGESTIONS.md)
- [Build 4 verification and remaining gates](docs/ORIVYN_RECONSTRUCTION_QA.md): 62 Python, 288 native and 27 UI tests passed with zero failures or test skips on exact source `791dc4755a0ab1039d3fd628a9480d1d4419d182`. Actual download, local inference and relaunch persistence passed.
- Unsigned ARM64 IPA: `Orivyn-0.1.0-build4-unsigned.ipa`, 4,192,549 bytes, SHA-256 `2e6084156b59d7cb0451a0bffc28cd3542264cca8416c4f508bb39ea2154be2c`. Requires iOS 26 or newer and signing before installation. Physical iPhone performance remains unverified.

The app has no paid tiers or in-app unlocks. Optional remote services are off by default and can have their own fees. External account integrations, autonomous scheduling, browser/computer control, hosted sites and image generation are explicitly unavailable, not simulated.

## Historical Jarvis-EVO baseline documentation

The following describes earlier candidates only, not validation of this reconstruction.

# Jarvis-EVO

An independent, original-branded native iPhone assistant for iOS 26 and newer. Not an OpenAI product. This repository is separate from Jarvis/GhostAI.

**Unsigned development candidate 2, not a completed release.** On 2026-11-12, Codemagic passed 34 Python tests, 78 native tests and 16 UI tests with zero skips, then built and verified the ARM64 iPhone package. The actual app downloaded Qwen, selected it, generated a local answer and retained the conversation/model selection after relaunch. Physical-device behavior and SideStore installation remain unverified. Advanced features are still pending.

## Verified candidate 2

- [Successful Codemagic run](https://codemagic.io/app/6af4edea52f6da2271c62b79/build/6af507f3b54d2e261c61f4b7): Xcode 26.0.1, Mac mini M2, iPhone 16 Plus simulator running iOS 26.0.
- Tested application source: `1be1c99cb6ca1c68b5425a6cdfb0240963768b16`. Exact CI commit: `65ae165a7183add9a23025442567c60ac437f90a`; its only additional change was an isolated Codemagic branch trigger. Later documentation-only commits do not change this tested-source identity.
- Unsigned `Jarvis-EVO-0.1.0-build2-unsigned.ipa`: version 0.1.0, build 2; **2,457,684 bytes**; SHA-256 `6b2cf99647adb9862a1d32e4664dbf6a244233a1ebde4d0ffd9e0bbe991f8ff5`.
- The prepared candidate attachment is named `Jarvis-EVO-0.1.0-build2-development-candidate-unsigned.ipa`. It contains the same verified bytes.
- Actual simulator captures: [light](docs/screenshots/build2-light-ios26-iphone16plus.png), [dark](docs/screenshots/build2-dark-ios26-iphone16plus.png), [sidebar](docs/screenshots/build2-sidebar-ios26-iphone16plus.png), [installed model](docs/screenshots/build2-model-installed-ios26-iphone16plus.png), [real local conversation](docs/screenshots/build2-local-conversation-ios26-iphone16plus.png).
- [Full QA evidence and remaining gates](docs/QA.md), [feature matrix](docs/FEATURES.md), and [reference research and fidelity limits](docs/UI_REFERENCE_RESEARCH.md).

The IPA does not include the roughly 491 MB model. Download or import weights in the app before using local chat. The app still requires signing before installation; no GitHub release or catalog entry has been published.

### Candidate 2 changes

- Compact, one-row composer; neutral toolbar; left history drawer; light/dark appearances and native message actions.
- Real in-app Qwen download, verification, selection, generation and relaunch coverage. The captured response is “The capital of France is Paris.”
- Broader text/PDF attachment, unsafe-path rejection, backup, real attachment-analysis inference and voice state-machine coverage.
- Build-number-aware IPA names and compact CI evidence archives, with original failure and packaging gates retained.

These are tested changes to the candidate, not a claim of exact visual matching or full feature parity. Separate image, voice and advanced-renderer work in progress is not included in this IPA.

## Architecture

- SwiftUI conversation interface with local SQLite history and editable memory.
- Real llama.cpp inference integration with an integrity-checked downloadable Qwen2.5 0.5B Q4_K_M model; not a canned-response engine. First download needs internet, subsequent inference is local.
- Optional Apple system model when Apple Intelligence is actually available.
- Optional HTTPS OpenAI-compatible endpoint selected by the user. No provider is labeled free; pricing and availability are the provider's responsibility. API keys belong in iOS Keychain, not source control.
- Local speech recognition where available, system text-to-speech, text/PDF document attachments and exports.
- Test, ARM64 build and IPA diagnostics preserve independent evidence. Unsupported capabilities are tracked in [the feature matrix](docs/FEATURES.md).

Small local models have lower capabilities than proprietary frontier models. The default model is approximately 491 MB on disk; context length, device memory and thermal limits constrain larger workloads. No paid API key is required for local inference.

## Build and verify

Requires macOS with Xcode 26, an iOS 26 simulator, Python 3 and XcodeGen. Install Xcode from Apple and select it. The runtime bootstrap downloads an official pinned llama.cpp XCFramework and validates its SHA-256 before use.

```sh
bash scripts/bootstrap_llama.sh
xcodegen generate
bash scripts/ci_macos.sh
```

The script runs Python verifier tests, native unit/UI tests, a build targeting physical ARM64 iPhones without signing, packages `Payload/JarvisEVO.app`, verifies Mach-O architecture/platform/deployment/frameworks, and writes a checksum plus diagnostic report. Building for a physical device is not the same as running on one. Generated evidence goes under `artifacts/`.

GitHub Actions is manual-only. Verify remaining free private-repository capacity before dispatching it. `codemagic.yaml` supplies the same build pipeline without automatic triggers or publication; repository access and free capacity must be authorized first. No paid billing is enabled by this project.

Pure package-verifier fixtures can run on Linux:

```sh
python3 -W error::ResourceWarning -m unittest discover -s scripts/tests -v
```

Fixtures verify rejection logic, not a real IPA. Native Swift tests require Xcode. The full CI script downloads and verifies actual test weights and requires the real-model smoke test. A manually run test without weights can skip; a skip must never count as a passing inference test.

## Privacy and installation

History stays in app-local SQLite by default. No analytics, synchronization or remote provider is enabled automatically. Downloading weights contacts the declared model host. Sending to a configured endpoint transmits the selected conversation context, extracted attachment text and saved memory to that endpoint. Review its privacy terms before enabling it.

See [SideStore installation](docs/SIDESTORE.md), [QA status](docs/QA.md), [feature matrix](docs/FEATURES.md) and [third-party notices](docs/THIRD_PARTY.md). An unsigned IPA still needs SideStore to sign it. LiveContainer compatibility is not verified.
