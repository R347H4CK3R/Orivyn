# Local inference: implementation and verification

## Selected implementation

Jarvis-EVO uses the actual C API of **llama.cpp b9049** through its official prebuilt Apple XCFramework. On an iPhone, layers are offloaded to Metal; simulator tests select CPU inference. No Apple Foundation Models availability, account, subscription, API key, or network connection is required to generate after model installation. The provider never falls back to a network service automatically.

The pinned official artifact includes iOS arm64 and iOS simulator arm64/x86_64. Its downloaded SHA-256 and actual XCFramework Info.plist were inspected. A newer b12292 official archive was investigated and deliberately not selected because its actual archive omitted the iOS simulator slice. Selecting b9049 is a compatibility decision, not a claim that it is the latest release.

Run `scripts/bootstrap_llama.sh` before resolving/building the Xcode project. The official ZIP nests its XCFramework beneath `build-apple/`; the script verifies the pinned digest before extracting to the local binary Swift package. Frameworks are generated dependencies and excluded from source control. The script refuses an invalid digest.

## Model and download behavior

Default: **Qwen2.5-0.5B-Instruct Q4_K_M**, official Qwen publisher, Apache-2.0, 491,400,032 bytes. This intentionally small starter is suitable for exploring an offline assistant but does not promise frontier-model reasoning, reliable tools, up-to-date knowledge, or benchmark performance on A18. iPhone memory, thermals and speed still require physical-device testing.

- Publisher revision: `9217f5db79a29953eb74d5343926648285ec7e67`
- SHA-256: `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`
- Runtime release archive SHA-256: `49c374bf78d98f53bfb3571b2285d315351ca6a5c1112191ae6f8b2616dec1d1`

Downloads require explicit user action in the app and HTTPS, check HTTP status, size, GGUF version and SHA-256, and install only after verification. Cancelled/invalid partial downloads are never selected. Device data/network charges are possible. The weights themselves are public downloads without a required account as checked during implementation; host availability may change.

User GGUF imports are copied into app-managed storage, limited to 2 GB, inspected, hashed, and recorded in a manifest. Import hashes detect later changes, not publisher authenticity. Users must verify imported sources/licenses. A GGUF header does not prove model compatibility: missing templates, unsupported architectures and memory failures surface as explicit errors during runtime loading. Only text-only GGUF instruction models with a chat template supported by llama.cpp's built-in formatter are supported in this version. No executable code is downloaded with weights.

Weights are excluded from iCloud backup and use iOS file protection. All bytes are rehashed before the local provider starts a request. A 2,048-token working context and 128-token prefill batches keep baseline memory/work bounded. The runtime tokenizer trims oldest complete messages, never the latest user message. A latest prompt that cannot fit fails explicitly. Extracted text attachments are included as bounded, labeled untrusted data; image pixels are not interpreted by this text model. Delimiters are descriptive guidance, not a prompt-injection security guarantee.

## Alternatives investigated

**MLX Swift / MLX Swift LM** are MIT-licensed Apple-silicon-native options with iOS support and convenient Swift model APIs. They remain a viable additional provider. This first implementation favors llama.cpp's single replaceable GGUF artifact, official Apple runtime, and explicit download/integrity policy. MLX requires coordinated tokenizer/config/weight assets and its current package has a broader dependency surface. Neither stack removes iOS memory limits or proves a model's A18 performance without testing.

**Apple Foundation Models** is an optional source-implemented provider that compiles but still requires runtime verification on eligible hardware. The default does not rely on Apple Intelligence being enabled or a system model being available.

## Tests and CI

`Tests/LocalModelStoreTests.swift` covers invalid imports, missing files, traversal, tampering, and removal. `Tests/LocalInferenceTests.swift` covers split UTF-8 tokens, attachment boundaries, bounded extraction, tokenizer-driven context selection, and an opt-in real model smoke test. No fake model emits a success response.

For the real-model job:

1. Run `scripts/bootstrap_llama.sh`.
2. Run `MODEL_PATH="$(python3 scripts/download_test_model.py)"`. This downloads roughly 491 MB and verifies exact size and digest. It prints only the verified absolute path on stdout.
3. Pass the path to the iOS simulator test process as `JARVIS_TEST_GGUF`, and set `JARVIS_REQUIRE_REAL_INFERENCE=1`. Add both as explicit Xcode scheme test environment variables. `SIMCTL_CHILD_JARVIS_TEST_GGUF="$MODEL_PATH"` and `SIMCTL_CHILD_JARVIS_REQUIRE_REAL_INFERENCE=1` are also useful for directly launched simulator processes, but do not rely on shell variables alone propagating through `xcodebuild test`.
4. Run the `LocalInferenceTests/testRealModelProducesOfflineTextWhenWeightsAreProvided` XCTest. A missing path with the required flag fails the test; an inaccessible file fails during import. The smoke test loads actual weights and asserts nonempty generated text.
5. Run the full unit/UI suite and perform physical iPhone airplane-mode tests. Stop/retry, memory-pressure handling, temperature, background transitions, and downloaded/imported-model swapping need device QA.

**Verification boundary:** [Codemagic attempt 6](https://codemagic.io/app/6af4edea52f6da2271c62b79/build/6af507f3b54d2e261c61f4b7) tested application source `1be1c99cb6ca1c68b5425a6cdfb0240963768b16` with CI commit `65ae165a7183add9a23025442567c60ac437f90a` on 2026-11-12. The only CI-source difference is the isolated Codemagic trigger. The iPhone 16 Plus / iOS 26.0 simulator passed 78 native and 16 UI tests, with no skips; 34 Python tests also passed.

The real-model smoke test passed in **2.767 seconds** and real imported-text attachment analysis passed in **14.876 seconds**. The actual app download/selection/conversation/relaunch test passed in **51.126 seconds**: it downloaded and verified Qwen through Models, selected the provider, waited for real generation to finish and confirmed the conversation, installation and selected model survived relaunch. The [actual screenshot](screenshots/build2-local-conversation-ios26-iphone16plus.png) reads “The capital of France is Paris.” The UI assertion checks a nonempty completed reply; the wording was confirmed visually. [Installed model capture](screenshots/build2-model-installed-ios26-iphone16plus.png).

These are entire test durations using CPU inference, not physical iPhone benchmarks. The host network was not disabled. Device airplane-mode behavior, Metal performance, cancellation, thermal behavior and memory pressure remain unverified. Candidate 2 is version 0.1.0 build 2; later documentation changes and separate image/voice/renderer work in progress do not change its tested source. See [QA.md](QA.md) for exact evidence and remaining gates.

## Official sources

- llama.cpp runtime, license, releases: https://github.com/ggml-org/llama.cpp
- Exact runtime release: https://github.com/ggml-org/llama.cpp/releases/tag/b9049
- Official XCFramework integration: https://github.com/ggml-org/llama.cpp/blob/master/docs/xcframework.md
- Model card/license: https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF
- Immutable model metadata: https://huggingface.co/api/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/revision/9217f5db79a29953eb74d5343926648285ec7e67?blobs=true
- MLX Swift: https://github.com/ml-explore/mlx-swift
- MLX Swift LM: https://github.com/ml-explore/mlx-swift-lm

License copies are in `ThirdPartyNotices/`. Preserve upstream notices when distributing the app. Downloaded model weights are not included in the source deliverable.

The standard `ci_macos.sh` downloads the pinned model before project generation and adds it only to the test bundle, not to the shipping application. `JARVIS_REQUIRE_REAL_INFERENCE=1` is passed through the scheme. The real-model test finds bundled weights when no explicit path is supplied, so this CI path must fail rather than skip missing weights. This path passed in the recorded native run; users still download or import weights separately in the app.
