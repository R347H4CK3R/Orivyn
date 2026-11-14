# Included private vision path — Linux verification, Apple gate outstanding

The private source now includes actual pixel inference in the image library:
visible eye action or Analyze image menu → explicit verified model setup →
question → real model output. `ORIVYN_NATIVE_VISION` requires the parent's combined
single llama framework exporting `ov_*`. Existing official-runtime builds still
compile without this flag and explain that the runtime is unavailable. No app
preview/release was published, no server or paid service is used, and no 1.0 or
physical-iPhone completion is claimed.

## Model and image correctness

Official pinned `ggml-org/SmolVLM2-2.2B-Instruct-GGUF` revision
`1bc3c9f74ceafd4c8d4411cc9cf188bba3798f91`, Q4_K_M text model plus f16 projector:
1,112,602,656 + 872,303,680 = **1,984,906,336 bytes**. Both exact LFS SHA256 values
were verified. This fits below the existing 2,000,000,000-byte file cap without
raising it; model file size is not an iPhone memory budget. Apache-2.0 declared
in both official conversion/base model metadata; standard license is retained at
`JarvisEVO/Resources/VisionModel-LICENSE.txt`. No LICENSE/NOTICE-named file was
advertised in those pinned model file lists. Full distribution clearance of
combined runtime dependencies remains a separate release requirement.

Audited existing bridge against pinned mtmd CLI: packed owned RGB goes into
`mtmd_bitmap_init`; the actual model chat template and actual mtmd image marker
are used; real chunk/token/position totals govern context checks. No filenames,
expected answers, OCR or metadata descriptions enter prompts. There was no
identified channel-order or template bug behind the baseline failures. The
stronger pair uses 81 image tokens in observed cases, versus 64 for the baseline.

Prompting is kept concise, and output exhaustion is now explicit status 8 with
partial text discarded, not successful truncation. The native Swift adapter also
rejects a 128-token cap and invalid UTF-8. Uniform RGB (all per-channel ranges
<=2/255) is rejected before model loading, status 10 / no visual detail. This is
pixel-only abstention, not an invented description; any real variation above
that threshold passes to the model. This narrow boundary is not a general
hallucination detector.

## Final same-fixture, same-prompt comparison

`extended_gate.py` preserves actual answers in `Evidence/production`:

| Fixed diagnostic | 500M Q8 | 2.2B Q4_K_M |
| --- | --- | --- |
| Four red/blue circle/square swaps | 4/4 | 4/4 |
| Circle left/right of square, swapped | 0/2 (both “Above.”) | 2/2 |
| Three circles | Pass | Pass |
| Natural mountain/river image | Pass | Pass |
| Uniform white blank | Abstains before model load | Abstains before model load |

Final gate: **500M 7/9, exit 1; stronger pair 9/9, exit 0**. The earlier broad
“describe briefly” prompt had only 2/5 baseline passes; concise prompting improves
that result, so the entire gain must not be attributed to model size. Before the
blank boundary, both models hallucinated on blank pixels (book cover / person in
room). All failing evidence remains retained in earlier artifacts. These nine
cases are a limited regression set, not broad natural-image accuracy acceptance.

Natural fixture comes from the existing pinned llama.cpp source at
`tools/server/webui/tests/stories/fixtures/assets/1.jpg`. Its transformed RGB hash
is recorded; the photograph itself is not redistributed here. Synthetic shapes,
spatial swaps and counts are generated directly. Model prompts do not expose the
fixture name or expected answer. Final stronger inference times were ~9.8–22.7s
on this shared Linux CPU, not phone latency claims. Blank abstention ~0.001s.

## Ownership and verified functionality

- `VisionPairStore`: process-wide private store, exact two-artifact verification,
  serialized install/verify, active lease forbids model replacement, stale-owner
  release cannot free a newer lease. Existing LocalModelStore supplies bounded
  download, exact SHA/size and atomic installation in a separate private root.
- `VisionImageFile`: O_NOFOLLOW/nonblocking regular-file reads; owned bytes,
  enforced 10MiB bound during read, cancellation, no mapped mutable user file.
- ImageBoundary: ImageIO metadata bounds, oriented <=512 thumbnail, sRGB white
  compositing, packed RGB and no-detail boundary. Apple decode remains unrun.
- `NativeVisionRuntime`: same VisionWorker/C bridge, pair lease survives until
  native close. `VisionSession` waits for text release, keeps heavy-work lease
  through teardown, and only then publishes an uncanceled complete answer.
- UI cleanup awaits work/session completion on cancellation, dismissal,
  backgrounding and lease revocation. Runtime code is behind the shared build
  flag; download is user initiated, and analysis never silently installs models.

Actual portable checks: 12 existing VisionSession scenarios; real pair-admission,
replacement, stale-owner/cancellation and pixel-boundary checks; 6 real filesystem
read cases; final Swift syntax parse. Exact production Session → pair actor →
NativeVisionRuntime → VisionWorker → C inference compiled under Swift6 complete
concurrency and passed actual red-square inference, teardown, and pair reacquire.
Only ImageIO and production file verification were substituted in that Linux
adapter test: generated RGB and a separately hash-verified immutable model
fixture directory. It is not a SwiftUI/AppModel/download/Apple integration test.
A real one-token generation returns status8, empty output and zero tracked
handles. `run_production_runtime.sh` reproduces the exact runtime compilation.

## Remaining verification

Apple SwiftUI/ImageIO/CryptoKit compilation, combined framework device/simulator
symbols and runtime uniqueness, actual download/cancellation on iOS, image
orientation/HEIC fixtures, physical offline operation, memory/jetsam and thermal
budgets, background transitions, latency and wider natural/spatial quality.
The projector-loading API has no progress cancellation callback; release can
wait for that stage. No parallel runtime, resource-cap increase, or native
verification is inferred from these Linux results.
