# Native generation phase diagnostics

`ov3_generate` emits one `ORIVYN_NATIVE_GENERATION_METRICS version=1` stderr line on every terminal call, including success and admission rejection. Fields contain only fixed enums, counts, statuses and monotonic wall-clock durations. No prompt, goal, output, model metadata or file path is added to this record. The public C ABI is unchanged.

The pinned llama context performance accessor is insufficient here: context parameters default `no_perf` to true, and the accessor clamps both token counts to at least one. Instead, the bridge observes its existing calls without changing context performance flags, scheduling, admission, schema, sampling, limits, or the production 60-second TTL.

Fields:

- `status`: existing `ov3_generation_status`, unchanged.
- `phase`: `admission`, `setup`, `prefill`, `sampling`, `generation`, or `validation` at the terminal check. Successful reservations end in `validation`.
- `prompt_tokens`: tokenized prompt size; `prompt_decoded`: prompt tokens accepted by successful decode calls.
- `sampled_tokens`: all sampled tokens, including EOG; `generated_tokens`: non-EOG sampled tokens, including any template stop tokens. Neither field contains token IDs or text.
- `prefill_calls`, `generation_calls`: decode calls attempted in each phase. `last_decode_status` is the last decode return code, or zero if no call occurred; interpret it with the call counts.
- `setup_ms`: tokenization and sampler preparation. `prefill_ms`, `generation_ms`: summed wall time inside decode calls. `sampling_ms`: sampling and acceptance. `validation_ms`: completion validation. `max_decode_ms`: largest single decode-call wall duration.
- `elapsed_ms`: time in the generation function, including cleanup and teardown. Session/template creation precedes this timer but still consumes the unchanged session TTL.

These measure API-call wall time, not device kernel time. On asynchronous backends, synchronization can occur during sampling or a later decode call, so elapsed work may be attributed there. The CPU simulator path is the immediate diagnostic target. No extra synchronization is inserted to alter runtime behavior.

An expiry (`status=3`) with `phase=prefill`, positive prefill counts, and zero sampled/generation counts identifies expiration before the first sampled token. Comparing `max_decode_ms` with the deadline identifies a slow synchronous decode that overshot a cooperative boundary. An expiry in generation after positive sampled counts is a different failure. These records diagnose; they do not extend the deadline or accept incomplete output.

## Reproduction

Build using `Diagnostics/NativeTools/build.sh` with the existing pinned b9049 source and combined static archives. Run:

```
python3 Diagnostics/NativeTools/test_generation_metrics.py \
  --model /path/to/verified/Qwen3-1.7B-Q8_0.gguf \
  --output /new/evidence/directory
```

The runner preserves stdout/stderr and decoded metrics. It executes the existing actual-model lifecycle tests, verifies their original status codes, and adds a short 500 ms test-only session to force real prefill expiry. It checks successful generation, admission expiry, prefill expiry, counts, finite timings and the strict content-free diagnostic field set. Production TTL remains 60,000 ms.

Linux success cannot establish the cause of the ARM iOS expiration. The new diagnostic lines still need capture from an Apple run before claiming whether its delay is prompt processing, sampling or generation.

## Observed Linux verification

The pinned official Qwen3-1.7B Q8_0 file (SHA-256 `061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a`) passed all 24 existing boundary/schema tests, including mismatched-template rejection. The actual lifecycle runner passed and produced 18 valid terminal diagnostic records with unchanged statuses, one-shot/context cleanup and borrowed-model ownership checks. The forced prefill expiry reported `status=3 phase=prefill`, 190 accepted prompt tokens, zero sampled tokens, and a 3689.074 ms maximum decode call; the short session is test-only.

A separate copy of the existing thread probe, linked to the instrumented library, used two CPU threads, context 2048, batch/ubatch 128, CPU KQV, mmap and default repacking. It returned the two expected read reservations with status 0:

| Measurement | Observed |
| --- | ---: |
| Load/context | 1.05927 s |
| Native call (external probe) | 49.2855 s |
| Prefill | 7116.083 ms, 190 tokens, 2 calls |
| Sampling | 28.654 ms, 33 sampled tokens |
| Generation | 42027.490 ms, 32 non-EOG tokens / decode calls |
| Validation | 4.819 ms |
| Maximum decode call | 4186.281 ms |
| Bridge elapsed, including cleanup | 49272.828 ms |

This individual Linux run is generation-dominated. It is slower than the earlier same-configuration 29.278 s probe; these sequential runs were not a controlled load comparison and do not establish a performance regression or improvement caused by diagnostics. No instrumentation-based workaround is applied.

Evidence is retained locally in `orivyn-native-generation-metrics-evidence`: source/binary hashes, raw lifecycle logs, parsed `METRICS.json`, boundary-test log, and the exact two-thread probe source/compile command/status/logs. No generated model catalog or capability metadata changes are required; the existing combined-runtime build hashes the changed bridge source.
