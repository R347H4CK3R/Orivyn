Update: Linux real-model cancellation and quality tests, plus a production lifecycle owner, are now recorded in [Linux/README.md](Linux/README.md). Apple/native claims below remain unrun.

# Orivyn isolated native vision harness

**Preparation only; native compilation/tests have NOT run.** No app integration,
CI launch, publication, VLM quality or physical-device success claim.

The BIOS harness remains frozen separately. This directory contains a small
XcodeGen iOS26 Swift6 app used only as an XCTest host. Its C bridge is an exact
copy of the sibling Linux-tested bridge (hashes in BRIDGE_PROVENANCE.json).

## What's prepared

- Real ImageIO metadata validation, single-frame and encoded/dimension limits,
  orientation-aware max512 thumbnail, sRGB white compositing and packed RGB.
- Single-use VisionWorker with owned immutable buffers, lock-reserved admission,
  independent atomic C cancellation, serialized worker exit/destroy, and close
  that waits for native resources. No pointer escapes. Exact status/report and
  actual output bytes retained; never substitute expected descriptions.
- 14 native test methods: seven image boundaries/orientation tests, four worker
  policy/release tests and three real-model encode/decode/cancellation tests.
  These tests were written before their corresponding Swift implementation but
  native RED/GREEN could not run here: no Swift/Apple SDK or new framework.
- `run_native.sh` is for the parent's bounded combined gate ONLY. It neither
  builds a framework nor downloads models nor launches CI. Required env:
  `VISION_MODEL_DIR` (absolute, immutable host path for simulator),
  `VISION_DESTINATION` (already chosen simulator destination). It forces
  `VISION_REQUIRE_REAL=1` so missing assets fail rather than skip acceptance.
- Exact pinned500M pair manifest, streaming safe local verifier and3 actual
  Python filesystem tests. No GGUF files copied, bundled or uploaded.

## Verification actually performed

Observed local RED for missing verifier, then all3 Python tests pass: exact
regular bytes, corrupt/size mismatch and symlink refusal. Actual existing pair
(436,806,912 +199,468,800 bytes) rehashed and matches both pinned SHA256 values.
Shell syntax passes. These results are NOT native ImageIO/vision evidence.
No native framework present, no xcodebuild invoked.

## One runtime, not two

Parent must first generate the combined llama.xcframework using the separately
reviewed b9049 mtmd build recipe, then copy it to `Frameworks/llama.xcframework`.
No dependency resolver or fallback release is configured. Only the application
links/embeds that framework; tests link the host app, not a second runtime.
C++ include path uses the same framework's ios-arm64 public headers (identical
C ABI across slices). Parent must still verify device/simulator symbols,
architectures and loaded-image uniqueness. OV_TESTING enables only native phase
cancellation/resource observation in this isolated test host, never a product.

## Important limits / next gates

The optional real-model tests skipped when running without explicit model path
are not a pass for vision. Required gate records generated red-circle PNG pixels,
actual model answer, status, image chunks, positions, tokens and resource count.
It asserts red+circle without filename/answer leakage. Cancellation at real CPU
encode/decode callbacks must return status2, empty output and zero owned handles.
A separate owner test cancels/closes while admitted and rejects overlap.

Resource counters are not a heap-leak proof. The host test's immutable model
folder is a CI contract, not a safe production attachment/model install API.
Production must use existing verified store and heavy-work admission barrier;
this standalone owner does not coordinate a separately loaded text model.
ImageIO HEIC decoding is possible but no HEIC fixture acceptance is claimed.
General vision quality remains unaccepted (prior Linux blank hallucination and
color omission remain known), as do airplane-mode physical iPhone latency,
thermal/memory/jetsam behavior and repeated text/vision switching.
No 1.0 completion or catalog model entry should be inferred.

Root llama MIT notice is retained. Parent's combined framework release still
requires transitive stb/miniaudio notices and full model Apache license/NOTICE
coverage; this unshipped source-only harness is not distribution clearance.
