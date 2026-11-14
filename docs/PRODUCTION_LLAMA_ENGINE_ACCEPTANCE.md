# Executed production Swift inference engine on Linux

`run_llama_engine_smoke.py` compiles exact production LlamaEngine, prompt builder, token decoder and value dependencies with Swift6.1.3 and actual llama.cpp b9049 shared libraries. It then runs the cached real Qwen2.5-0.5B-Instruct-Q4_K_M GGUF. No CLI inference, provider double, prewritten response or replacement engine is used.

Six checks passed in runs5and6: actual streamed “hello” reaches genuine end-of-generation; invalid generation settings are rejected; a one-token limit is reported as incomplete rather than success; simultaneous admission is rejected while busy; unload cancels and joins an active generation; a new response succeeds after release/reload. Run6 compiler/runtime exit0, approximately5.55seconds including compilation. Host timing is not iPhone performance.

Linux's release uses separate backend shared objects, so the test driver explicitly loads them from the provided runtime directory. That bootstrap is not shipped engine behavior and does not validate Apple's framework linkage/backend startup. Initial run1 reported no loaded backend; its throwing test main terminated. Run2 exposed the missing test-driver ggml link; run4 exposed a test-driver attempt to mutate a let property. These harness failures are preserved, not claimed as app defects.

Official b9049 headers came from https://raw.githubusercontent.com/ggml-org/llama.cpp/b9049/include/llama.h and its ggml/include dependencies. The runner requires supplied headers/runtime/model and performs no downloads. SOURCE-MANIFEST and RUNTIME-MODEL-MANIFEST record exact hashes; TOOLCHAIN, COMMAND, RESULT and raw runtime logs preserve evidence. This is local integrity evidence, not independently verified vendor signing.

The app's Swift engine was not modified in this pass. Native iOS framework, GPU/Metal, UI, app lifecycle, signed installation, thermals and physical device remain unverified. The six executable checks are not added to XCTest totals. No general model semantic/tool-calling reliability claim, paid CI or release publication.

## Bundled grammar integration extension
Exact production grammar is now copied alongside the Linux test executable and included in its source manifest. This validates Linux Bundle.main lookup only, not Apple app packaging.
The initial expanded harness failed with LocalAgentError.unavailable because its resources had not been copied. After adding the exact resource, all eight checks passed in llama-grammar-green: the prior six checks plus actual constrained generation in required-tool and unrestricted-decision modes. Outputs were get_app_info with empty arguments and an answer containing hello.
These two simple decisions do not establish general agent semantic correctness, earlier multi-step failures remain unresolved. No production engine or grammar behavior changed. Physical iPhone and Apple framework execution remain unverified.

## Failed-load and context recovery extension
Eleven checks passed with exact production Swift and actual GGUF in llama-recovery-2. Added real-tokenizer rejection of an oversized system prompt without silently dropping it, missing model load error, and successful valid-model reload after a failed model switch.
llama-recovery-1 exposed a test expectation error: the documented system-budget rejection is ProviderError.rejected, not LocalModelError.promptTooLong. The assertion was corrected; production code was unchanged. Runtime error logs for the intentionally absent model are expected.

## Reproduced and repaired stale model cache
Actual production engine generated from old mapped weights after a disposable model path was atomically replaced with an invalid 10-byte file. Independent reviewer reproduced this; the permanent regression failed in llama-cache-red.
Engine reuse now requires matching file identity (device/inode/size/modification time), not merely the pathname. Missing metadata disables reuse. LocalModelStore SHA-256 verification remains required; metadata is cache invalidation, not security validation or a guarantee against concurrent hostile in-place writes.
llama-cache-green passed all twelve actual engine checks, including rejecting the newly replaced invalid file rather than generating from stale weights. The test hardlinks weights to a disposable same-filesystem directory and renames a separate file over that link; original weights are never written. Expected invalid-model diagnostics are retained.
This fixes the atomic replacement cache path on the tested Linux host. Apple filesystem behavior and iPhone runtime remain unverified. A separate same-ID provider-descriptor refresh concern remains for follow-up; it is not resolved by this engine change.

## Real context-use acceptance
llama-context-1 passed fifteen checks. Three new factual fixtures executed the exact Swift LlamaEngine/LocalPromptBuilder with Qwen2.5-0.5B and produced the expected distinct names:
- Supplied document extractedText: Cobalt Finch.
- Prior user/assistant conversation: Copper Owl.
- A saved note selected by exact MemoryContextBuilder: Silver Badger.

No provider responses were mocked. Document text is a supplied fixture, not proof of native file extraction. Memory selection is actual production logic but this test does not read persisted memory storage. These short factual checks do not establish broad reasoning, adversarial prompt robustness, long-document accuracy, or all-model quality. Linux execution remains distinct from iPhone validation.
