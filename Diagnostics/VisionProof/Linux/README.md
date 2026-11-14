Follow-up: the private production path and stronger-model comparison are documented in [PRODUCTION_VISION.md](PRODUCTION_VISION.md). The original evidence below is historical and remains retained.

# Linux vision lifecycle and real inference evidence

Private source development only. No new UI, catalog activation, publication,
model-limit change, network runtime, or 1.0 completion claim.

## Implemented

`JarvisEVO/Core/VisionSession.swift` owns the existing shared `.vision` heavy-work
lease. It waits for text-model release before invoking the runtime, cancels
independently, waits for worker and native close, and keeps failed teardown
revoked. It defers result publication until release and rejects empty/over-16KiB
UTF-8 output. Dismissal, caller cancellation and lease revocation discard pending
answers, including while close is suspended. AppModel conforms in
`Services/VisionLeaseOwner.swift`. No product runtime is enabled. A future caller must await close on dismissal,
backgrounding and lease revocation; dropping the owner is not a cancellation API.
Invalid input also awaits close so pre-owned runtime resources are released.

The proof host's `SessionVisionRuntime` connects this owner to ImageBoundary and
VisionWorker. Its paths still require the proof's immutable hash-verified pair;
production pair installation/store and caller activation remain unfinished.
The bridge now cancels during llama model loading using the real progress
callback, reporting cancellation rather than load failure. Projector loading
still has no progress cancellation callback in this API.

## Observed tests

- 12 exact-production-source Swift 6 strict-concurrency lifecycle scenarios pass,
  using the recovered official static Swift libraries. Includes pending text
  release, worker/close release barriers, failed close, cancellation before load,
  revoked lease, empty/oversize UTF-8 output, invalid input, teardown cancellation,
  concurrent close and another feature's active lease. Test runtime is a controlled
  fake; these are not native model, ImageIO or AppModel compilation tests.
- Actual pinned SmolVLM-500M Q8 + f16 projector hashes verified. The real C++
  bridge compiled against existing b9049 mtmd/llama/ggml static libraries.
- Real load/encode/decode cancellation: status 2, empty output, zero tracked
  handles in all three phases. Load cancellation completes in ~0.07 seconds in
  this run; encode ~0.27s; decode ~2.81s. Not device latency bounds or heap proofs.
- Five real synthetic-image probes: two circle checks pass, three fail. Red
  square omitted red and said rectangle; blue square said rectangle; white blank
  hallucinated a detailed book cover. Exact outputs/reports and input RGB hashes
  are retained in Evidence/results.json. **Quality gate exited 1**, intentionally.
  Square-as-rectangle is an exact-label failure; blank hallucination and missing
  red are substantive quality failures. No general vision acceptance is claimed.
- Existing pair verifier: 3 tests pass. Native recipe: 3 tests pass. Initial
  sandbox/cwd test invocation failed; corrected writable test invocation and
  recipe working directory pass. No Apple compiler or SDK was run.

## Reproduce

Provide existing pinned llama source and Linux static build directories; no
script downloads or starts services. The model pair is verified before loading.

```sh
bash Diagnostics/VisionProof/Linux/build.sh "$LLAMA_SOURCE" "$LLAMA_BUILD" /tmp/vision.so
python3 Diagnostics/VisionProof/Linux/real_gate.py /tmp/vision.so "$VISION_MODEL_DIR" /tmp/vision-evidence
bash Diagnostics/VisionProof/Linux/run_session_checks.sh "$SWIFTC" /tmp/vision-session-checks
```

The real gate uses Pillow only to generate synthetic RGB. Neither fixture names
nor expected color/shape labels are included in the common model question. It
retains failed answers and returns nonzero on any quality or lifecycle failure.
It is a small diagnostic, not a comprehensive broad-vision benchmark. Input
files, heap leaks, natural objects, spatial relations/counting, ImageIO HEIC,
orientation, actual combined iOS linkage, simulator execution, device memory,
thermal/background behavior and physical offline acceptance remain unverified.
