# Model-bound native suggestion policy candidate

This development change adds explicit model identity binding for the reviewed Q4 candidate. It does not change the default model, catalog, downloader, file cap, production 60-second TTL, two-tool authority, output schema, approval flow, or generation implementation. Apple/device verification remains pending.

| Policy | Verified model SHA-256 | Exact embedded template |
| --- | --- | --- |
| 1, original Q8 | `061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a` | Original 4100 bytes |
| 2, Q4 candidate | `d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5` | Candidate 4116 bytes |

Q4 provenance: `ggml-org/Qwen3-1.7B-GGUF`, pinned revision `daeb8e2d528a760970442092f6bf1e55c3b659eb`, `Qwen3-1.7B-Q4_K_M.gguf`, 1,282,439,264 bytes. This is a ggml-org conversion, not an official Qwen Q4 publication. Model bytes and the exact embedded candidate template were verified in the isolated comparison evidence. The two templates differ in tool-response recognition; they are not treated as generally equivalent. Separate review compared 30 single-user native bridge inputs and found identical common-chat prompt/parser/grammar outputs; that does not establish multi-turn equivalence.

`ov4_create_borrowed` takes an explicit trusted policy ID. Each policy compares only its own pinned template, plus the existing qwen3 architecture check. Unknown IDs have no fallback. Legacy `ov2_create_borrowed` and `ov3_create_borrowed` remain policy 1 only and reject the Q4 candidate.

The C API assumes the trusted owner has authenticated model bytes, as before. The production provider calls `store.verifiedURL(for:)` first, then maps the verified descriptor SHA to `NativeReadPolicy`; an unknown SHA fails before engine admission. `GenerationRequest` has no policy selector. The separate engine argument must be present exactly when `nativeReadGoal` is present, checked before acquiring a worker. The engine uses the policy with the same retained model/context owner and cancellation/unload barrier. Ordinary chat and reviewed execution permissions are unchanged.

The combined-runtime validator now requires the additive `ov4_create_borrowed` symbol. The host single-runtime build records both pinned template headers in its source hashes; the CI cache already hashes native headers. The public bridge header is copied into the same existing llama module by the existing packaging recipe.

## Verification

Completed portable checks in this isolated branch:

- C policy creation: both exact matches, both cross-policy mismatches, unknown IDs 0/3/999, legacy Q8-only behavior, mask/TTL/NUL boundaries.
- Actual production Swift Q4 actor: exact SHA mapping, missing/extra engine-policy rejection, shared-engine exclusion, actual two-read proposal, cancellation plus awaited unload, reload, and normal chat afterward.
- Production provider/session host harness: revocation while verification is delayed; unknown descriptor SHA rejected after verification and before engine admission. The store in this harness is explicitly a host scaffold, not proof of a new cryptographic implementation; production LocalModelStore verification is unchanged.
- Four actual ov4 Q4 goals on the exclusive model worker: correct two-read/app-only/models-only reservations; forbidden delete/upload goal rejected with status 10 and null output. One-shot, cache cleanup and borrowed-model ownership checks passed.
- All 24 legacy Q8 boundary tests passed, including rejection of the Q4 model through the legacy API.
- Eleven combined-runtime validator tests and Linux combined-library link: new symbol present once, no second llama/ggml runtime, no undefined symbols.

The first concurrently started Q4 four-goal and Q8 boundary reruns were interrupted with exit 130 when the shared host became resource-constrained. Those partial logs are preserved and are not passes or performance evidence. Final reruns use one exclusive model worker, sequentially. Evidence is retained under `orivyn-native-model-policy-evidence` with actual actor source hashes, commands, logs and separate interrupted/rerun files.

Reproduce after the normal native bridge build:

```
Diagnostics/NativeTools/policy-tests /verified/q8.gguf /verified/q4.gguf
Diagnostics/NativeTools/policy-goal-tests /verified/q4.gguf
```

The production actor runner accepts `--policy 2 --model /verified/q4.gguf`; its default policy remains 1. No native iOS acceptance or general autonomy completion is claimed.
