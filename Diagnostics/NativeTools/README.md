# Native read generation driver

The private production integration is compiled only with ORIVYN_NATIVE_TOOLS and the combined runtime. It connects the engine-owned model/context to native suggestions and the existing explicit review/create/run flow. The default stock-runtime build does not activate it. No Apple, simulator, Metal or iPhone validation. No release or preview publication. This removes a real native generation-driver gap and demonstrates a below-download-cap model; it does not complete general autonomy.

`ov3_create_borrowed` takes an existing engine-owned model, reviewed read-tool mask/budget, deadline, and 1–2048 byte user goal (no embedded NUL). It admits the exact pinned Qwen3 template/architecture and offers only reviewed tools. `ov3_generate` uses the same native Jinja prompt, grammar, lazy triggers, preserved tokens, stops and PEG parser, then returns only `reserved_not_executed` batches. No read or other action is executed here. Only `get_app_info` and `list_models` with empty arguments are accepted.

The caller must retain model and context for the complete synchronous call, serialize context ownership and session destruction, and provide an empty single-sequence context. Existing KV contents cause rejection and remain untouched. Admitted contexts are cleared on exit. Every generation attempt is one-shot, including failures; the session becomes cancelled at completion. `ov2_cancel` can run concurrently, but destruction must wait for generation to return. Cancellation/deadline checks surround synchronous decode and parser calls; this is cooperative, not a hard preemption guarantee. Stop/EOG detection is internal, never supplied by model prose. Truncated token-budget output cannot reserve calls. The API assumes a trusted owner has already verified the model's file hash; template/architecture checks alone do not authenticate weights.

## Reproduce on Linux

Requires a C++17 compiler, Python, and a combined static PIC build at exact llama.cpp commit `2496f9c14965c39589f53eea31bdb6d762b1d360` (b9049). CombinedRuntime evidence describes Linux link verification; it is not an Apple packaging recipe. Do not link another llama/ggml copy into the app.

```sh
export LLAMA_SOURCE=/path/to/llama.cpp-b9049
export LLAMA_BUILD=/path/to/combined-build/llama
# For an already verified source archive without .git:
export LLAMA_SOURCE_COMMIT=2496f9c14965c39589f53eea31bdb6d762b1d360
bash build.sh
python download.py --output /path/to/model.gguf
./driver-tests /path/to/model.gguf
TEST_MODEL=/path/to/model.gguf MISMATCHED_MODEL=/path/to/other-template.gguf python tests.py
```

The public Apache-2.0 evaluation model is official `Qwen/Qwen3-1.7B-GGUF`, revision `90862c4b9d2787eaed51d12237eafdfe7c5f6077`, file `Qwen3-1.7B-Q8_0.gguf`, size **1,834,426,016 bytes**, SHA-256 `061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a`. Download code verifies size and digest before renaming. It fits the unchanged 2,000,000,000 byte file cap. Process memory is larger than file size; Linux RSS is not iPhone memory certification. Weights and binaries are excluded.

## Production integration and remaining gates

- LlamaEngine now retains model/context through the native call and joins generation before unload. The provider admits only verified pinned model bytes. Cancellation, occupied-engine admission, unload/reload and normal chat are covered by the host production harness. Delayed verification/revocation is a separate production session/provider harness. Neither substitutes for device acceptance.
- One combined pinned Apple runtime containing common Jinja/PEG without duplicate llama/ggml symbols; Apple link/Metal/device memory validation.
- Native suggestions enter the existing reviewed-plan ownership/CAS/deadline coordinator. The user still reviews the two permitted metadata reads and explicitly creates/runs the plan. This bridge itself executes no action and does not implement general autonomous decisions.
- Broader held-out reliability/resource measurements and model admission policy. Tiny deterministic probes do not establish general autonomous ability. Default model and resource guards are unchanged.

## Recorded evidence

`evidence/tests.log`: eight lifecycle scenarios (pre-cancel, invalid token limit, cancellation during real prefill, incomplete token-limit output, two successful two-read generations with context reuse, expiry, occupied-context preservation); four goal-creation boundary checks; and three additional real goal probes. Both single-tool held-out requests returned their permitted read; the delete/upload adversarial request returned no reservation. Every run checks one-shot behavior, null output on failure and cache cleanup where admitted. `evidence/boundary-tests.log`: 24 inherited parser/ownership tests passed using real model vocabulary, including a different-template rejection. Model process wall time was 25.94 seconds with peak RSS 2,088,100 KiB in this Linux environment. These deterministic small probes do not establish broad reliability. The full raw runtime metadata log is retained locally outside the source package.

Production harness: `scripts/run_native_read_smoke.py` records exact Swift source hashes and commands, with actual model inference or `--admission` for delayed-verification revocation. See the private capability record for integrated evidence.
