# Development vision path — historical Linux evidence and simulator smoke

**Apple checkpoint:** [recorded CI evidence](../../../docs/evidence/apple-ci-20261114/RESULT.json)
for source `ed914a5a81da73b5fbd63293458b4efabfb56320` reports that
`ProductionVisionRuntimeTests.testRequiredProductionPNGInferenceAndRelease`
passed on iPhone 16 Plus / iOS 26.0.1 arm64 **simulator**, Xcode 26.3, in
**123.483 seconds** in [run 43628873176](https://github.com/R347H4CK3R/Orivyn/actions/runs/43628873176).
That one test exercised a generated red-square PNG, production ImageIO/RGB,
full pinned hashes, NativeVisionRuntime/worker/combined C inference, an answer
containing red and square, and acknowledged close/pair reacquisition. It did
**not** exercise VisionSession/UI, establish broad accuracy, or measure a physical
iPhone's memory/thermal behavior. The question-label UI fix described below is
later than that checkpoint and is not covered by its pass.

The nine-case results and logger regression below are **historical Linux CPU
checks**, separate from that one Apple simulator test. Their scope must not be
upgraded to nine simulator passes or general vision acceptance.

The development source now includes actual pixel inference in the image library:
visible eye action or Analyze image menu → explicit verified model setup →
question → real model output. `ORIVYN_NATIVE_VISION` requires the parent's combined
single llama framework exporting `ov_*`. Existing official-runtime builds still
compile without this flag and explain that the runtime is unavailable. No app
preview/release was published, no server or paid service is used, and no 1.0 or
physical-iPhone completion is claimed.

## Who processes pixels, consent, and data flow

This feature uses the **local SmolVLM2 2.2B vision-language model**, not the
currently selected chat provider. `NativeVisionRuntime` → `VisionWorker` → the
`ov_*` C bridge invokes llama.cpp's **mtmd** vision encoder/projector and local
language-model decoding in the same runtime. It has no remote inference provider,
cloud fallback, OCR-as-vision substitution, or tool-execution path. An answer does
not authorize or trigger any autonomous action.

In the production source, `VisionImageFile` reads the already imported,
app-owned image into bounded owned bytes. Apple's **ImageIO** validates metadata
and decodes an orientation-aware thumbnail (maximum dimension 512); CoreGraphics
normalizes sRGB and composites transparency onto white, then packs RGB pixels.
Only those pixels and the user's question enter model inference. The image's
filename, OCR extraction, and metadata descriptions do not enter the prompt.
The Apple decoding path was subsequently compiled and exercised for the one
simulator smoke described above. The historical Linux nine-case gate instead uses Pillow-generated RGB for the synthetic fixtures and
Pillow-decoded RGB for the existing natural photograph. The separate production
Swift adapter check also substitutes generated RGB for unavailable ImageIO.

Consent is two explicit app actions: **Download or verify vision model** fetches
or verifies the pinned weights; **Analyze image** runs analysis of the selected
existing image and the question shown in the field. Opening the image-analysis
screen does neither automatically. Analysis never silently downloads a missing
pair. Downloads use HTTPS from Hugging Face's pinned model URLs (including its
asset-delivery redirects); this network operation requests model files only.
**No image pixels, questions, or answers are uploaded by this feature.** After
verified installation, inference itself is local and requires no network. Actual
physical-iPhone airplane-mode operation remains an outstanding test.

There is no new per-image OS camera or photo-library permission request: this
screen reads an existing imported attachment. Any system file-picker selection
and security-scoped access occurred during the prior import; the imported copy
is then read from the app's private attachment storage. The Analyze button is
app-level consent, not a claim that iOS displays an additional permission dialog.

The current screen holds the question in SwiftUI state and the answer in the
in-memory `VisionSession`. Analyze captures an immutable submitted question,
which is shown beside the answer; the editable draft is disabled during work
and cleanup and becomes editable afterward. Editing a later draft does not
relabel an existing answer. It does **not** automatically append either to chat,
write an analysis history/backup, or save a new image. Existing imported image
storage is unchanged. Cancel/dismiss/background cleanup cancels work and clears
the session answer while resources finish releasing; this is not a secure-memory
erasure guarantee. The user may explicitly select/copy displayed text. The prior mtmd/clip logger
printed actual question text to stderr; that concrete leak is now fixed as
described below. This is not an audit or no-logging guarantee for every other app
component. Developer diagnostic scripts deliberately save fixture prompts,
actual answers, and hashes locally as evidence; they were run on generated
fixtures and the specified repository photograph, not private user images.

## Model and image correctness

Official pinned `ggml-org/SmolVLM2-2.2B-Instruct-GGUF` revision
`1bc3c9f74ceafd4c8d4411cc9cf188bba3798f91`, Q4_K_M text model plus f16 projector:
1,112,602,656 + 872,303,680 = **1,984,906,336 bytes**. Both exact LFS SHA256 values
were verified:

- `SmolVLM2-2.2B-Instruct-Q4_K_M.gguf` SHA256:
  `0cf76814555b8665149075b74ab6b5c1d428ea1d3d01c1918c12012e8d7c9f58`.
- `mmproj-SmolVLM2-2.2B-Instruct-f16.gguf` SHA256:
  `db9a3a1648cab1ebc3af4a2b0c8145dd8faebf6f7dd7b16e7dc1842229f14ac4`.

The exact manifest is `Evidence/production/MODEL_PAIR.json`. This fits below the
existing 2,000,000,000-byte file cap without
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

The **nine** checks below are the actual assertions in `extended_gate.py`,
not nine categories of general vision capability. For each nonblank case the
script requires C status 0 and the listed case-insensitive **substring** matches.
It does not perform semantic grading or reject every additional incorrect claim.
The final gate also requires zero tracked native handles for every case; this
counter is not a heap-leak proof.

| Check | Fixed input | Exact question | Output assertion |
| --- | --- | --- | --- |
| 1 | Red circle, white background | “Describe the visible image in one sentence.” | Contains `red` and `circle` |
| 2 | Red square, white background | Same question as check 1 | Contains `red` and `square` |
| 3 | Blue circle, white background | Same question as check 1 | Contains `blue` and `circle` |
| 4 | Blue square, white background | Same question as check 1 | Contains `blue` and `square` |
| 5 | Red circle left of blue square | “Where is the circle relative to the square? Answer in one sentence.” | Contains `left` |
| 6 | Same shapes with positions swapped | Same question as check 5 | Contains `right` |
| 7 | Three red circles in a row | “How many circles are visible? Answer briefly.” | Contains `three` or `3` |
| 8 | Existing mountain/river photograph | “Describe the visible scene in one sentence.” | Contains `mountain` or `cliff`, and `water`, `river`, or `lake` |
| 9 | Uniform white RGB image | Same question as check 1 (not sent to a model) | Status 10, empty output, zero evaluated positions |

Check 9 is **pixel-boundary abstention, not successful model inference**. The
blank guard prevents a call that previously hallucinated. Checks 1–8 actually
encode pixels and generate model text. Synthetic images are 384×384; the natural
image is resized to fit within 512×512. Both pairs receive identical fixtures and
questions. The recorded outputs, reports, model identities, and transformed RGB
hashes are in `Evidence/production/baseline-results.json` and
`Evidence/production/stronger-results.json`.

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
  compositing, packed RGB and no-detail boundary. The subsequent Apple smoke
  exercised this path for the generated red-square PNG.
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

## Verification scope and remaining work

The historical nine-case and logger-regression runs used **Linux CPU execution**: two threads,
`n_gpu_layers=0`, mtmd `use_gpu=false`, a 2048-position context, and at most 128
output tokens. They do not demonstrate Apple Metal execution, an iOS simulator,
a signed iPhone build, camera use, or general agent autonomy. Passing eight
inference fixtures plus one blank guard is not broad real-world accuracy,
robustness, accessibility, safety-critical interpretation, or release acceptance.


Beyond the recorded one-case simulator pass, remaining vision acceptance includes
the actual VisionSession/UI workflow (including the later submitted-question
label), actual download/cancellation on iOS, required orientation/HEIC evidence,
loaded-runtime uniqueness, physical offline operation, memory/jetsam and thermal
budgets, background transitions, device latency and wider natural/spatial quality.
The evidence checkpoint also does not establish full-suite completion or release
acceptance; consult that run's separate results rather than infer them here.
The projector-loading API has no progress cancellation callback; release can
wait for that stage. No parallel runtime, resource-cap increase, or native
verification is inferred from these Linux results.


## Prompt-bearing native log fix

Before the fix, mtmd/clip `LOG_DBG` / `add_text` diagnostics wrote the actual
question to stderr. `ov_create` now calls `mtmd_log_set` with a static no-op
callback through `std::call_once`, before the first owned vision session is
returned. The callback has no session/user-data pointer and remains valid for
the process lifetime. It suppresses **all mtmd/clip message text**, including
messages whose formatting could contain prompts; `ov_report` status, phase,
tokens, positions and resource counts remain the diagnostic boundary.

This setter changes a **process-global mtmd/clip logger**. The application uses
one combined runtime and this bridge owns its mtmd entrypoints. Other code in
that process must not independently reset that logger or start unmanaged mtmd
work. Configuring once avoids per-request changes or restoration racing with
active native callbacks. The fix does **not** call `llama_log_set`,
`ggml_log_set`, change the text-model logger, redirect stderr, or suppress the
separate mtmd-helper's non-prompt encode/decode progress messages.

Old and fixed bridges were compiled locally; `log_privacy_check.py` runs them
in separate processes against the verified pinned 2.2B pair. A generated red square and a unique
synthetic question marker—not a private image or question—reproduce the issue.
The old privacy assertion fails because the marker appears in captured stderr;
the fixed assertion passes because it does not. Both runs return status 0, the
**identical actual red-square answer**, and zero tracked live handles. Llama
loader diagnostics remain in fixed stderr, demonstrating that the text/runtime
logger was not globally muted. Exact library/source/log SHA256 values, reports,
and the synthetic old-leak excerpt are retained under `Evidence/log-privacy`.
Full raw logs remain local under `artifacts/vision-log-privacy/results`.

Reproduce with separately built old and fixed shared libraries:

```sh
python3 Diagnostics/VisionProof/Linux/log_privacy_check.py OLD_SO FIXED_SO VERIFIED_MODEL_DIR OUTPUT_DIR
```

These are real **Linux CPU** logger-regression results. The subsequent combined
Apple simulator smoke above does not itself repeat the old/new stderr privacy
regression, so that privacy assertion remains backed by its separate Linux
evidence. Other diagnostics, crash reporting, and unrelated providers are outside
this focused regression.
