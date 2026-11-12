# Isolated b9049 iOS vision bridge preparation

Status: design and locally syntax-tested build recipe only. No Apple compiler,
CI launch, native vision test, main-app change, or catalog claim. 2026-11-12.

## Evidence and fixed build graph

b9049 resolves to commit `2496f9c14965c39589f53eea31bdb6d762b1d360`.
`source-integrity.json` verifies 15 downloaded source files as Git blobs against
that exact official commit tree, plus SHA-256. Initial `ggml/LICENSE` request
returned 404; do not invent a separate license file. Root LICENSE is MIT.

Current Packages/LlamaRuntime/Package.swift exposes a single binary `llama`
module from Frameworks/llama.xcframework. The official b9049 framework script
sets LLAMA_BUILD_TOOLS=OFF and packages no mtmd header or archive. Its frameworks
are dynamic Mach-O binaries force-loading combined static archives, NOT merely
standalone static frameworks. Keep this architecture; replace the one dependency
rather than linking a second llama/ggml implementation alongside it.

Exact graph: root requires LLAMA_BUILD_COMMON && LLAMA_BUILD_TOOLS to configure
tools; tools adds mtmd. Library mtmd includes mtmd-helper.cpp, clip.cpp,
image/audio helpers, and model implementations. It publicly links ggml+llama,
privately Threads::Threads, requires C++17 and explicitly forbids linking
llama-common. CLI targets use llama-common; do not build them for iOS.

`prepare_build.py` takes only the audited upstream script SHA-256 and generates
`build-ios-mtmd.sh`. Changes:
- iOS 17 deployment (matching existing package), tools ON;
- build only target mtmd, parallel 2, for arm64 device then universal arm64/x86_64
  simulator (script's current order is simulator then device), sequential;
- add tools/mtmd/<Release-sdk>/libmtmd.a to the existing exact archive set:
  libllama, libggml, libggml-base, libggml-cpu, libggml-metal, libggml-blas;
- copy mtmd.h + mtmd-helper.h and expose them in existing `framework module llama`;
- preserve upstream Metal embedded library, Accelerate, Foundation, libc++, SDK
  flags, force-load packaging, install name, dSYM generation, platform marking;
- omit all macOS, tvOS, visionOS builds and their cleanup.

Do not modify current bootstrap checksum to accept this different artifact.
After native validation, introduce separately named build provenance and expected
archive checksum for this replacement. Existing public b9049 release hash is
still valid only for the original release.

## Reproducible build procedure (NOT EXECUTED)

Use an isolated full official source checkout at the exact commit above. Confirm
`git diff --exit-code HEAD` and exact HEAD, record `xcodebuild -version`, SDK
versions, CMake version, host architecture and script SHA. Run the generated
script from that checkout on an already authorized Mac/CI worker, not Linux.
No package install or source-download fallback exists in this script.
Run generator tests first. Record wall time and peak build memory externally.
Do not invoke the upstream seven-platform script.

Required postbuild checks before integration:
1. Info.plist device arm64 and simulator arm64+x86_64 slices; vtool platform and
   deployment targets; lipo architectures; dsym UUID matches binary.
2. `nm -gU` each slice exports llama_model_load_from_file, llama_init_from_model,
   llama_decode, mtmd_init_from_file, mtmd_bitmap_init, mtmd_tokenize,
   mtmd_helper_get_n_pos, mtmd_helper_eval_chunk_single, mtmd_free. No new
   dependency on a second libllama/libggml dynamic image; inspect `otool -L`.
3. Tiny Swift `import llama` compile references both original llama and mtmd C
   APIs. Device link/build plus simulator load/run; original text inference must
   still pass with exactly one runtime image in process.
4. Preserve all notices; archive final framework, compute SHA-256 and record
   compiler/source/recipe provenance. Do not treat byte-for-byte reproducibility
   across differing Xcode/dSYM timestamps as already established.

Build cost unknown here. Planning allowance only: roughly 10–25 minutes for
these three architecture builds on a hosted Mac, plus 5–15 minutes for existing
app build/tests. Two jobs constrain concurrent compiler memory, but no measured
Mac RSS exists; provision an ordinary 8+ GB build host and measure, rather than
claiming a RAM guarantee. Use one time-capped combined gate after source is ready,
not one CI run per header issue. With ~89 free minutes left, a 25-minute combined
cap leaves headroom but could time out; never extend/launch automatically.

## Licenses / notices

Root llama.cpp (including ggml tree): MIT, preserve root LICENSE verbatim.
mtmd-helper.cpp compiles stb_image and miniaudio even though bridge uses RGB.
stb_image.h provides MIT or public-domain choice; preserve MIT notice.
miniaudio.h provides public-domain or MIT No Attribution choice; preserve full
bundled license and embedded third-party notices as conservative distribution
practice. Source copies are saved under source/vendor. Full-source notice audit
remains a release gate; do not assume two headers exhaust transitive notices.
No llama-common or HTTP tools linked. Apple's system frameworks come from SDK.
Model pair remains separate Apache-2.0 assets, provenance in integrity.json and
saved model cards. Keep Apache license/NOTICE obligations on eventual download
packaging; saved cards alone are not a substitute for required license text.

## Bridge boundary and ownership

Proposed C++ private wrapper, C ABI only to Swift; compile against the SAME
module/runtime. Never expose native pointers to UI. An actor/coordinator owns
one engine slot: text OR vision, never both. Existing LlamaEngine.unload() can
return while busy by setting unloadWhenIdle; it is NOT an awaitable release
barrier. Add a verified idle-and-release handshake before granting vision slot.
On cancel/switch: set an atomic cancellation token immediately from an independent
callback, await worker exit/resource release, only then load another model.
Never free native state concurrently with native compute.

Suggested methods (design, not implemented):
- `prepare(imageURL, question, verifiedPair) -> OwnedPreparedImage`
- `generate(prepared, cancellationToken) -> AsyncThrowingStream<String, Error>`
- `cancelAndRelease() async` resolves only after every owner is released.

Input acceptance: exactly one owned local image, verified regular file and
existing attachment limits (10 MiB, 40 MP, each dimension <=16,384). No arbitrary
URLs, symlinks, live user-selected external handles, audio, or multiple frames.
Use ImageIO metadata before decode. Create thumbnail with
kCGImageSourceCreateThumbnailFromImageAlways=true,
kCGImageSourceCreateThumbnailWithTransform=true,
kCGImageSourceThumbnailMaxPixelSize=512 and caching disabled on source.
Validate resulting dimensions <=512 and positive, normalize orientation and
render sRGB with white alpha composite. Convert explicit RGBA to tightly packed
RGB (3*w*h, checked multiplication <=786,432 bytes). Reject corrupt/unsupported
images rather than decode full-resolution or silently fall back to OCR. HEIC
can use ImageIO; do not pass HEIC bytes to stb helper. Prompt never includes the
fixture filename or expected label. Keep app's existing OCR-only capabilities
truthful until this path is actually selected and succeeds.

Load text model+projector after old engine released; validate model/projector
hashes as one pair and mtmd_support_vision. CPU-first baseline n_threads=2,
use_gpu=false, n_gpu_layers=0, offload_kqv=false; evaluate device Metal later,
not as an inferred result of this CPU proof. One fresh llama context n_ctx=2048,
n_batch/n_ubatch=128. Output limit <=128 for initial acceptance. Keep model
chat template and one actual media marker; reject user injection of additional
media markers. mtmd_bitmap_init accepts RGBRGB bytes; keep backing memory alive
through native calls even if internal copy behavior changes.

Tokenize with mtmd_tokenize, inspect real chunks and require exactly one image.
Use BOTH actual get_n_tokens and get_n_pos rather than text-only estimates;
reserve output + special tokens and fail/trim oldest text only before eval if
position+output exceeds 2048. No fixed '64 image tokens' assumption: observed
384px fixtures used64 but model preprocessing may change. Never trim the image
marker away. Evaluate chunk-by-chunk via mtmd_helper_eval_chunk_single,
check all return codes/new_n_past and cancellation between chunks/tokens.
Use terminal EOS and bounded output byte accounting as well as token cap.

Cancellation: Task cancellation alone is insufficient during synchronous encode.
mtmd_context_params has cb_eval + user data. Exact ggml scheduler callback
contract: return true for ask=true to request observation, then return false
when ask=false and cancellation atomic is set, stopping graph compute at a
scheduler boundary. This may split batches and impact performance; benchmark.
llama context abort_callback is documented CPU-only in this revision. Use it
for CPU decode plus chunk checks; do not promise immediate Metal cancellation.
Atomic state must outlive callbacks and be free of Swift actor calls. Already
submitted GPU work can finish before cleanup; no hard120s in-process kill on
phone. Bounded image/context limits and measured cancellation latency are required.

RAII/defer cleanup on EVERY success/error/cancel: sampler, input chunks, bitmap,
RGB/image objects, mtmd context, llama context, then llama model. All dependent
contexts destroyed before model. Do not backend_free globally per request while
any other engine may exist. On finish or background memory warning release
model/projector as well, not only KV cache. Reuse may be considered only after
measurement and must preserve one-slot limit.

## Acceptance matrix / next combined native gate

Local tests already run: recipe rejects changed upstream input; two builds only;
mtmd target/headers/archive inclusion; shell syntax; probe bounds/pinned pair
constants. Five tests pass. These are NOT C++/Swift compilation or vision tests.

Author native wrapper tests first, then production bridge (isolated branch):
- fake allocator/backend counts: inject failure at each allocation/eval stage;
  live handles and slot count return zero; wrong pair rejected before load;
- cancellation before load/during encode/during decode/after final token; no
  callbacks after owner released, no canceled persistence, no deadlock;
- text-to-vision and vision-to-text wait for old resources; concurrent request
  rejected/queued explicitly, never two models resident;
- EXIF rotations1–8, transparent PNG, HEIC, truncated bytes, animated/multiframe,
  huge dimensions/size, symlink, multiple images: bounded output or explicit error;
- actual image-position accounting at context boundary, extra marker rejection,
  EOS and output cap, failure propagation (not empty success).

One useful native gate can combine: compile/package/symbol smoke; existing text
engine regression; wrapper lifecycle/policy tests; simulator CPU real-image four
fixture probe with same prompt and OCR disabled. Expect blue color omission and
blank hallucination from Linux: record them, do not silently weaken assertions
or call general vision accepted. Add paired color/shape swap, spatial relation,
counting and natural-object fixtures before product quality claims. No user media.

Physical iPhone16Plus acceptance remains REQUIRED: airplane-mode operation,
first/repeated image latency, phys_footprint high-water mark (not Linux RSS),
thermal/memory-warning/jetsam behavior, background/foreground cleanup, repeated
switching and cancellation latency. Actual available memory varies; 8GB device
RAM is not an8GB process budget. Linux ~774MB RSS is not an iOS allocation limit.
No vision catalog entry or UI claim until native real-image and physical budget
acceptance criteria are agreed and met.
