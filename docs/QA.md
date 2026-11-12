# QA evidence and remaining release gates

Jarvis-EVO candidate 2 has a verified simulator run and a structurally verified unsigned iPhone package. It is an **unsigned development candidate**, not a fully accepted or release-ready app.

## Successful native run: 2026-11-12 UTC

- [Codemagic attempt 6](https://codemagic.io/app/6af4edea52f6da2271c62b79/build/6af507f3b54d2e261c61f4b7).
- Application source: `1be1c99cb6ca1c68b5425a6cdfb0240963768b16`.
- Exact build commit: `65ae165a7183add9a23025442567c60ac437f90a`, branch `ci/qa-1be1c99-green-6`. GitHub comparison shows only `codemagic.yaml` differs, adding the isolated branch trigger. Later documentation-only commits do not change which source was tested.
- GitHub check “Jarvis-EVO iOS candidate verification” completed successfully at **00:36:49 UTC** for that exact build commit.
- Host: Mac mini M2. Xcode 26.0.1, build 17A400. Simulator: iPhone 16 Plus, iOS 26.0, ARM64.
- **34 Python tests passed**, covering package rejection, model integrity, build-number-aware filenames and reliable evidence export.
- **78 native tests passed**, zero failures and no skipped tests: AppModel 7, AttachmentAnalysisIntegration 1, AttachmentAppFlow 5, AttachmentService 17, Conversation 7, LocalInference 3, LocalModelStore 5, LocalPromptBuilder 4, Persistence 8, Provider 7 and VoiceService 14.
- **16 UI tests passed**, zero failures and no skipped tests: nine application-flow tests and seven visual/interaction tests.
- Xcode recorded `TEST SUCCEEDED`. The Release build for `generic/platform=iOS` recorded `BUILD SUCCEEDED`.
- Independent review counted **94 passed XCTest cases**, no failed/skipped cases, and confirmed the 34-test Python summary. “App Intents metadata extraction skipped” is a build warning, not a skipped test.

### Real local inference and in-app model installation

Three distinct real-model checks passed:

1. `LocalInferenceTests/testRealModelProducesOfflineTextWhenWeightsAreProvided`: **2.767 seconds**. Imports verified GGUF weights, loads llama.cpp, streams nonempty output and unloads.
2. `AttachmentAnalysisIntegrationTests/testRealLocalModelAnswersFromImportedTextAttachment`: **14.876 seconds**. Uses a real local model to answer from imported text.
3. `JarvisEVOVisualUITests/testRealDownloadedModelProducesAndPersistsConversation`: **51.126 seconds**. Starts the actual app download, checks verified installation, selects the provider, sends a prompt, waits for completed output, captures it, and verifies conversation/model selection after relaunch.

The actual conversation capture reads “The capital of France is Paris.” It is produced by the app's local model, not a fabricated screenshot or canned response. The UI test asserts a nonempty completed response and persistence; the Paris wording was confirmed by reviewing the screenshot.

- Runtime: llama.cpp **b9049**. Official XCFramework archive SHA-256: `49c374bf78d98f53bfb3571b2285d315351ca6a5c1112191ae6f8b2616dec1d1`.
- Model: Qwen2.5-0.5B-Instruct Q4_K_M, **491,400,032 bytes**, publisher revision `9217f5db79a29953eb74d5343926648285ec7e67`.
- Model SHA-256: `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`.
- Simulator inference used CPU. Durations cover their entire tests and are not tokens-per-second measurements or physical iPhone benchmarks.
- The host network was not disabled. These tests do not establish physical-device airplane-mode operation, Metal behavior, model quality or long-conversation reliability.

### Attachment and voice test boundaries

Attachment service tests cover UTF-8/JSON and selectable multi-page PDF extraction, bounded text, encrypted/malformed/scanned PDFs, empty/oversized/unsupported files, independent copies, cleanup, traversal, directories and symbolic links. App tests cover attachment count limits, removing pending files, failed imports, backups and unsafe mixed restores. UI tests exercise repeated Files-picker cancellation and history-import cancellation. These are specific automated cases, not proof of every document or device workflow.

The 14 voice tests cover permission outcomes, repeat starts, cancellation races, retries and synthetic interruption/route/media-reset notifications. Permission responses and interruption events are simulated. Actual microphone capture, recognition availability, audio routes and read-aloud playback on an iPhone remain unverified.

### Unsigned package

- CI artifact: `Jarvis-EVO-0.1.0-build2-unsigned.ipa`.
- Prepared candidate attachment name: `Jarvis-EVO-0.1.0-build2-development-candidate-unsigned.ipa`, identical bytes.
- App identifier: `app.jarvisevo.ios`; version **0.1.0**, build **2**; minimum iOS **26.0**.
- Size: **2,457,684 bytes**.
- SHA-256: `6b2cf99647adb9862a1d32e4664dbf6a244233a1ebde4d0ffd9e0bbe991f8ff5`.
- `scripts/verify_ipa.py` was independently rerun on the retrieved IPA and passed physical-device ARM64 Mach-O, deployment target, bundle structure and embedded `llama.framework/llama` dependency checks.
- Neither app nor framework contains an `LC_CODE_SIGNATURE` command. No `_CodeSignature` resources or provisioning profile are present. It must be signed before installation.
- Model weights are not included. Signing, installation and runtime behavior on a physical iPhone are separate, unrun gates.
- No GitHub release or catalog entry has been published.

### Actual screenshots and provenance

All five images below were exported from `Tests.xcresult` for this run and visually reviewed. Each is a 1290×2796 iPhone 16 Plus simulator screenshot, not a mockup.

| Capture | Test | Exported attachment | SHA-256 |
|---|---|---|---|
| [Light](screenshots/build2-light-ios26-iphone16plus.png) | `testIdleComposerKeepsAllControlsOnOneRow` | `E7882356-9778-4D01-8C75-A4094686470D.png` | `fcd0a0d7a6c92763ef3fe218eb5f17b0cfce9a8c1f2a3dec68e303c70c14b5dd` |
| [Dark](screenshots/build2-dark-ios26-iphone16plus.png) | `testCaptureDarkAppearanceAndMultilineDraft` | `A93A7D90-C425-4545-9D7F-A79274B5CA42.png` | `e465856011119beb28fa07816580ede80d75e9007443c7f3e7dbac2fe8220d20` |
| [Sidebar](screenshots/build2-sidebar-ios26-iphone16plus.png) | `testHistoryIsLeftDrawerAndDismissalPreservesDraft` | `C9A93291-752A-4395-A111-6DBCF902D5C1.png` | `8c37dffbcb1421aaba9bb9ab8b2fa72085ce06a14161cfcaf03c626267d1d006` |
| [Installed model](screenshots/build2-model-installed-ios26-iphone16plus.png) | `testRealDownloadedModelProducesAndPersistsConversation` | `AA7A947D-721D-4C02-A6EC-31125AC95B53.png` | `62e7f30d99de7be546ffb0f8fd820b95bfa4695766e0d43908a26fe182e8b289` |
| [Real conversation](screenshots/build2-local-conversation-ios26-iphone16plus.png) | `testRealDownloadedModelProducesAndPersistsConversation` | `BFF72B82-865F-4B72-839C-672A8F74F6BB.png` | `57db228b393cda1a5682a977c2433c76522ce5b35175222f342f39241d879190` |

The composer is now one row at a 52pt standard minimum, compared with the earlier 93.67pt capture. The UI geometry test passed its ≤66pt control-height tolerance. The official promotional reference was estimated at about 52.8pt after width normalization. These are approximate geometry comparisons, not pixel-perfect or full-parity acceptance. See [UI_REFERENCE_RESEARCH.md](UI_REFERENCE_RESEARCH.md).

### Retained CI evidence

Artifact directory: `artifacts/20261112T002802Z-1106/`. Retained files include `package-tests.log`, `native-tests.log`, `Tests.xcresult`, `device-build.log`, `ipa-verification.json`, `SHA256SUMS`, Xcode/SDK/simulator metadata and exported screenshots with a manifest.

Compact evidence archives and the complete result bundle were retrieved. SHA-256:
- `logs-evidence-001.zip`: `abc318aec543fe04b5320c430e6215a8b88fef8c466aff92bff36bcfed6da898`.
- `screenshots-evidence-001.zip`: `942c35561683cdb4d93544072ca40601619c5f0c3c8dda4a8ed3f2da2af7a61a`.
- `artifacts.zip`: `b9679ca8dbea11247b1714cf6391d02e4922da39390972ad0d26b32e08769d86`.

Native test results were reviewed from the CI logs and screenshot manifest. The full `Tests.xcresult` is retained for Xcode inspection; no new native run was performed on the Linux verification host. The passing build still contains non-fatal warnings, including App Intents extraction warnings.

## Earlier evidence

Candidate 1 was tested on 2026-11-11: source `3628cf57c49a57d116140780d3973761e8a1c336`, CI `db4d8714a110956f370c00fb8b4c92eef53d3844`, 17 Python, 41 native and seven UI tests. Its version 0.1.0 build 1 IPA was 2,410,998 bytes with SHA-256 `5a4c7bfabe65245b262991aecbc79fa55a6c86992d84bbac18302cd02faedeed`. That older package and its screenshot are not candidate 2.

Earlier red runs exposed Swift concurrency diagnostics and unsafe attachment path handling. The current full green gate includes the repairs and regression tests. Intermediate source, focused tests or later work-in-progress commits must not be presented as this verified binary.

## Still required before broader release claims

- Physical iPhone 16 Plus: signed installation, launch, download/import flow, airplane-mode chat, stop/retry, background transitions, low-memory recovery, Metal inference, speed, thermals and battery use.
- SideStore signing, device pairing, installation and refresh; LiveContainer compatibility.
- Real hardware voice permissions, on-device dictation, interruptions/route changes and playback.
- Broader document/file-picker flows, branch/edit/regenerate/copy/share UI, memory editing, accessibility and additional screen sizes.
- Live remote-endpoint authentication/streaming/Keychain behavior, Apple Foundation Models on eligible hardware and network transitions.
- Closer visual acceptance against owner-supplied screenshots or an actual reference app session. Official promotional references establish only limited layout evidence.
- Remaining advanced features in [FEATURES.md](FEATURES.md). Separate image/voice/renderer work in progress is not included in this tested candidate.

Preserve exact commits, logs, test counts/skips, model/runtime hashes, screenshots and package checks for every future candidate. Passing this simulator suite does not complete the original full feature request.
