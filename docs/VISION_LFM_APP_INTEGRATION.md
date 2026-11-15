# LFM vision app integration

This isolated branch selects the tested, unprefixed official LFM2.5-VL 1.6B Q6_K/f16 pair for the existing image-analysis provider. It does not change the selected text/chat provider, execute tools, or send image pixels to a remote service. The C bridge and original pixel coordinates are unchanged. Main and published build 9 remain separate; the parent must verify its final combined source and Release IPA before publication.

## User flow and data preservation

Download or verify vision model remains an explicit user action, using pinned HTTPS Hugging Face model URLs and exact bounded SHA256/size verification. Analyze image never downloads missing weights. Imported images continue through the owned-file/ImageIO/RGB boundary and local native inference. Existing Smol files and Apache notice are retained; users of that prior pair must explicitly install the new pair to use this candidate. No user attachment, conversation, or old model file is deleted. Pair lease/install exclusion and cancellation paths are unchanged.

The screen shows the model name, 1.82 GB download, full LFM Open License 1.0 text and source attribution before setup, plus a specific warning that counts and shape distinctions can be wrong. If the bundled license is unavailable, setup is disabled. The official license has commercial-use restrictions and redistribution obligations; it is not Apache 2.0. Its exact bytes are retained as JarvisEVO/Resources/LFM-Vision-LICENSE.txt, SHA256 61d7e939a05911c765b7e98ffaa1ab5ca6c0174a65350766c25cb10197d19fc8. This source integration is not a determination that every commercial deployment is licensed.

## Verified portable evidence

Run 43681174499, source a03ca637: unchanged frozen ten-case diagnostic 9/10 versus Smol 8/10. The reversed horizontal case is corrected, but four circles plus a square still produces 5. Expanded strict holdout 15/18 versus baseline 12/18; all shifted relative positions and absolute halves pass. Two landscape outputs say valley, which the narrow predeclared answer set rejects despite plausible semantics. These strict scores do not establish general image accuracy.

Run 43681967233 rebuilt the original bridge from a03ca637 and verified 9/9 legacy checks, 8/8 real ABI cases (four normal inferences, three phase-injected native cancellations, one blank guard), and one-token output-limit rejection with empty text and zero tracked handles. A generic counting prefix regressed ordinary descriptions and was rejected; it is not present here. Evidence is preserved in docs/evidence/vision-lfm-original-regressions-20261115.json. Tracked handle counts are not heap-leak or memory-budget proofs.

## Verified Apple checkpoint

Run 43682659679 tested source f8663e9e3d2a71d0c6c3bd5a8623b08ffa9cc7bb using Xcode 26.3 and iPhone 16 Plus / iOS 26.0.1 arm64 simulator. Exactly one test passed, with zero failures and zero skips. The app compiled with both native feature flags. The required test checked the exact bundled license bytes, production PNG/ImageIO decoding, real VisionModelStorage full-file hash verification, NativeVisionRuntime/worker/C inference, acknowledged close and pair reacquisition.

The actual answer was “A red square is visible.” Native runtime duration was 35.740 seconds and XCTest duration was 39.455 seconds. These are simulator measurements, not physical-device latency. Model revision and both SHA256 values match the pinned LFM candidate. All runner outcome checks, including the required execution marker, succeeded. Artifact 14149767705 and selected raw evidence are retained in docs/evidence/vision-lfm-app-simulator-20261115.json.

This one smoke does not exercise VisionSession, the live analysis UI, the user download flow, or the broader quality fixtures on Apple. Later branch commits add package validation and documentation; the recorded native source checkpoint remains f8663e9.

## Release gate and remaining limits

The release package validator requires the exact LFM notice in CFBundleVersion major 10 or later and preserves historical builds 1–9. All 32 actual ZIP regression tests pass in run 43682924391, source 4e15aa0; twelve focused in-memory resource cases also pass. This proves the validator's checks, not that a future Release IPA has passed them. The final parent build must use major 10 or later and verify its real IPA.

Physical-device offline operation, memory/jetsam, thermal behavior, latency, wider image/OCR quality, live UI download/cancellation and final combined-source Release verification remain separate gates. No general autonomous vision/tool behavior or 1.0 completion is claimed.
