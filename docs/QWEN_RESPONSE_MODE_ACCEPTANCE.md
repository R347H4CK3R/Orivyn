# Optional concise Qwen3 chat mode

The baseline catalog test found both Qwen3 models emitted thinking text before the answer. This is a model mode, not corrupt output. The official Qwen3 README documents explicit non-thinking template support (enable_thinking=False); the C llama chat template API has no such switch.

A separate source experiment tested a Qwen3 empty-thinking prefill. It did not alter shipping source and its generic driver metadata was corrected with an explicit experiment notice. Actual generation then omitted thinking text, without stripping any emitted tokens. Punctuation differences remained and were not reclassified as strict instruction passes.

The implementation adds an explicit, persisted “Concise Qwen 3 answers” toggle, default off. It applies only to normal local chat requests using architecture qwen3 and a known ChatML assistant suffix. Unknown Qwen3 templates fail closed; other architectures remain unchanged. The prefill is included by the same formatter used for real-tokenizer budgeting and generation. Raw generated output remains untouched. Remote/system providers and the separate model-driven agent do not consume this option.

qwen-mode-red failed with the flag present but not implemented. qwen-mode-guarded passes seven actual runtime checks: false/true/false for both cached Qwen3 variants, plus unchanged output from Qwen2.5 when the option is toggled. Concise outputs were hello and Hello.; this is not a fix for arbitrary instruction fidelity. Independent source review found no defect in the targeted implementation.

Native setting persistence/request propagation regression was added to AppModelTests and the manual Apple gate, but has not executed. SwiftUI binding, Apple runtime and physical iPhone verification remain pending. No release or catalog mutation.
