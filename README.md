# Jarvis-EVO

An independent, original-branded native iPhone assistant for iOS 26 and newer. Not an OpenAI product. This repository is separate from Jarvis/GhostAI.

**Unsigned development candidate, not a completed release.** On 2026-11-11, Codemagic passed 17 Python tests, 41 native tests (including real local GGUF inference), seven UI tests, an ARM64 iPhone build and package verification. Physical-device behavior and SideStore installation remain unverified. Advanced features are still pending.

## Verified candidate

- [Successful Codemagic run](https://codemagic.io/app/6af4edea52f6da2271c62b79/build/6af4f3b60f2c5fc818ff6d6c): Xcode 26.0.1, Mac mini M2, iPhone 16 Plus simulator running iOS 26.0.
- Tested application source: `3628cf57c49a57d116140780d3973761e8a1c336`. The exact CI commit was `db4d8714a110956f370c00fb8b4c92eef53d3844`; its only additional change was an isolated Codemagic branch trigger.
- The real-model smoke test passed in 13.492 seconds with actual Qwen2.5 0.5B Q4_K_M weights. This is the entire simulator test duration, not an iPhone speed benchmark or proof of airplane-mode operation.
- Unsigned `Jarvis-EVO-0.1.0-unsigned.ipa`: 2,410,998 bytes; SHA-256 `5a4c7bfabe65245b262991aecbc79fa55a6c86992d84bbac18302cd02faedeed`.
- [Actual simulator screenshot](docs/screenshots/main-screen-ios26-iphone16plus.png) and [full QA evidence and remaining gates](docs/QA.md).

The IPA does not include the roughly 491 MB model. Download or import weights in the app before using local chat. The app still requires signing before installation; no GitHub release or catalog entry has been published.

## Architecture

- SwiftUI conversation interface with local SQLite history and editable memory.
- Real llama.cpp inference integration with an integrity-checked downloadable Qwen2.5 0.5B Q4_K_M model; not a canned-response engine. First download needs internet, subsequent inference is local.
- Optional Apple system model when Apple Intelligence is actually available.
- Optional HTTPS OpenAI-compatible endpoint selected by the user. No provider is labeled free; pricing and availability are the provider's responsibility. API keys belong in iOS Keychain, not source control.
- Local speech recognition where available, system text-to-speech, document attachments and exports.
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

History stays in app-local SQLite by default. No analytics, synchronization or remote provider is enabled automatically. Downloading weights contacts the declared model host. Sending to a configured endpoint transmits the selected conversation context and extracted attachment text to that endpoint. Review its privacy terms before enabling it.

See [SideStore installation](docs/SIDESTORE.md), [QA status](docs/QA.md), [feature matrix](docs/FEATURES.md) and [third-party notices](docs/THIRD_PARTY.md). An unsigned IPA still needs SideStore to sign it. LiveContainer compatibility is not verified.
