# Jarvis-EVO

An independent, original-branded native iPhone assistant for iOS 26 and newer. Not an OpenAI product. This repository is separate from Jarvis/GhostAI.

**Development candidate. No verified iOS build, inference run, screenshots or installable IPA has been published yet.** Source implementation is underway. A source file or a successful package-fixture test is not proof of working native behavior.

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

The script runs Python verifier tests, native unit/UI tests, a physical ARM64 build without signing, packages `Payload/JarvisEVO.app`, verifies Mach-O architecture/platform/deployment/frameworks, and writes a checksum plus diagnostic report. Generated evidence goes under `artifacts/`.

GitHub Actions is manual-only. Verify remaining free private-repository capacity before dispatching it. `codemagic.yaml` supplies the same build pipeline without automatic triggers or publication; repository access and free capacity must be authorized first. No paid billing is enabled by this project.

Pure package-verifier fixtures can run on Linux:

```sh
python3 -W error::ResourceWarning -m unittest discover -s scripts/tests -v
```

Fixtures verify rejection logic, not a real IPA. Native Swift tests require Xcode. The optional real-model smoke test must receive actual weights and may not be counted as passed if skipped.

## Privacy and installation

History stays in app-local SQLite by default. No analytics, synchronization or remote provider is enabled automatically. Downloading weights contacts the declared model host. Sending to a configured endpoint transmits the selected conversation context and extracted attachment text to that endpoint. Review its privacy terms before enabling it.

See [SideStore installation](docs/SIDESTORE.md), [QA status](docs/QA.md), [feature matrix](docs/FEATURES.md) and [third-party notices](docs/THIRD_PARTY.md). An unsigned IPA still needs SideStore to sign it. LiveContainer compatibility is not verified.
