# QA evidence and remaining release gates

Jarvis-EVO has a verified simulator test run and a structurally verified unsigned iPhone package. It is an **unsigned development candidate**, not a fully accepted or release-ready app.

## Successful native run: 2026-11-11

- [Codemagic attempt 2](https://codemagic.io/app/6af4edea52f6da2271c62b79/build/6af4f3b60f2c5fc818ff6d6c).
- Application source commit: `3628cf57c49a57d116140780d3973761e8a1c336`.
- Exact build commit: `db4d8714a110956f370c00fb8b4c92eef53d3844`, branch `ci/native-3628cf5-attempt-2`. The only difference from the application source commit is the isolated Codemagic push trigger. Later documentation changes do not change which source was tested.
- Host: Mac mini M2. Xcode 26.0.1, build 17A400. Simulator: iPhone 16 Plus, iOS 26.0, ARM64.
- **17 Python tests passed**, covering package rejection and model-integrity fixtures.
- **41 native tests passed**, zero failures and no skipped tests: AppModel 7, Conversation 7, LocalInference 3, LocalModelStore 5, LocalPromptBuilder 4, Persistence 8 and Provider 7.
- **Seven UI tests passed**, zero failures and no skipped tests: actual screenshot capture, empty-composer send guard, model-picker draft preservation, saved-chat relaunch, settings dismissal, suggestion selection and unavailable-provider error handling.
- Xcode recorded `TEST SUCCEEDED`. The Release build for `generic/platform=iOS` recorded `BUILD SUCCEEDED`.

### Real local inference

`LocalInferenceTests/testRealModelProducesOfflineTextWhenWeightsAreProvided` passed in **13.492 seconds**, with actual model weights rather than a test response. The test imports the verified GGUF, loads llama.cpp, streams a reply, asserts nonempty output and unloads the model. The required-inference flag was enabled; this test was not skipped.

- Runtime: llama.cpp **b9049**. Official XCFramework archive SHA-256: `49c374bf78d98f53bfb3571b2285d315351ca6a5c1112191ae6f8b2616dec1d1`.
- Model: Qwen2.5-0.5B-Instruct Q4_K_M, **491,400,032 bytes**, publisher revision `9217f5db79a29953eb74d5343926648285ec7e67`.
- Model SHA-256: `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`.
- Simulator inference used the CPU path. The test duration includes import/load/generation/cleanup; it is not a tokens-per-second measurement or a physical iPhone benchmark.
- CI downloaded weights before testing. The test does not disable the host network and does not prove physical-device airplane-mode behavior, fallback during connectivity changes, model quality or long-conversation reliability.

### Unsigned package

- File: `Jarvis-EVO-0.1.0-unsigned.ipa`.
- App identifier: `app.jarvisevo.ios`; version 0.1.0, build 1; minimum iOS 26.0.
- Size: **2,410,998 bytes**.
- SHA-256: `5a4c7bfabe65245b262991aecbc79fa55a6c86992d84bbac18302cd02faedeed`.
- Package verifier passed for physical-device ARM64 Mach-O, deployment target, bundle structure and the required embedded `llama.framework/llama` dependency. The downloaded model is not included in the shipping app.
- Package checks were also rerun against the retrieved IPA. Signing, installation and runtime behavior on a physical iPhone are separate, unrun gates. No release or catalog entry has been published.

### Evidence retained

The run's artifact directory is `artifacts/20261111T230314Z-1092/`: `package-tests.log`, `native-tests.log`, `Tests.xcresult`, `device-build.log`, `ipa-verification.json`, `SHA256SUMS`, Xcode/SDK/simulator metadata and exported screenshot attachments.

[Actual main-screen screenshot](screenshots/main-screen-ios26-iphone16plus.png) was captured by `JarvisEVOUITests/testCaptureMainScreenScreenshot()` on the iPhone 16 Plus simulator. It shows the reset app before model installation, not a generated reply. SHA-256: `84dab37b9a41ad5ae70e91063f899207f87b35f5e621e2c5e0151e99791fdeae`.

The successful logs contain non-fatal upstream Metal compiler warnings and Xcode warnings about App Intents metadata extraction and supported orientations. This was a passing run, not a warning-free build.

## Observed failure and repair

[Attempt 1](https://codemagic.io/app/6af4edea52f6da2271c62b79/build/6af4eef00f2c5fc818ff52c4), exact commit `54b0a5adefc3d2e2a49752097ba91ee59789bfc0`, failed Swift compilation with two data-race diagnostics for raw model/vocabulary pointers captured in the prompt-trimming callback. No native tests or device package ran in that attempt.

Source repair `3628cf57c49a57d116140780d3973761e8a1c336` captures the existing resource owner and obtains pointers inside the synchronous actor-isolated callback. Strict Swift 6 concurrency checks, tests and release gates were retained. Attempt 2 then compiled and passed the full suite above.

## Earlier local evidence

Initial package-verifier fixtures were observed failing before implementation and passing afterward. Later regressions cover framework type/deployment, ZIP aliases/collisions and model integrity. The full current Python suite contains 17 tests. Shell syntax checks and Swift syntax parsing were useful preliminary checks, but were never counted as native compilation or runtime tests.

## Still required before broader release claims

- Physical iPhone 16 Plus: signed installation, app launch, download/import flow, actual airplane-mode chat, stop/retry, background transitions, low-memory recovery, Metal inference, speed, thermal behavior and battery use.
- SideStore signing, device pairing, installation and refresh; LiveContainer compatibility. An unsigned IPA cannot be installed directly without signing.
- Voice permission flows, on-device dictation availability, interruption/route changes and read-aloud playback on hardware.
- PDF extraction and file-picker workflows, attachment limits, larger and malformed imports, UI branch/edit/regenerate/copy/share, memory editing, accessibility, dark mode and layout on additional screen sizes. Existing model/state/persistence tests cover specific cases, not all of these end-to-end flows.
- Real remote-endpoint authentication, streaming failures, redirect refusal and Keychain behavior; Apple Foundation Models on eligible hardware; network-transition fallback. Parser/endpoint validation tests are not live service integration tests.
- Visual fidelity comparison with owner-supplied references. No reference media accompanied the retrieved brief; one real app screenshot does not establish fidelity.
- Remaining advanced features in [FEATURES.md](FEATURES.md), including web research/citations, image understanding/generation/editing, richer documents, tool execution, scheduling and encrypted sync.

Preserve exact commits, logs, test counts/skips, model/runtime hashes, screenshots and package checks for each future candidate. Do not equate the current passing simulator suite with completion of the original full feature request.
