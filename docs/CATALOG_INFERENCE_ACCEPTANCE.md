# Actual Swift catalog inference matrix

catalog-inference-1 compiled the exact production Swift LlamaEngine and used all nine cached catalog GGUF files with matching llama b9049. Each received the same simple greeting instruction, temperature zero, maxTokens 128, through production chat-template formatting. Every model loaded and reached normal generation completion.

Strict one-word instruction results: five passed, four mismatched. The runner correctly exits 1, not an all-pass claim.
- Passed: Qwen2.5 0.5B Q4_K_M and Q5_K_M; Qwen2.5 Coder 0.5B and 1.5B Q4_K_M; SmolLM2 1.7B Q4_K_M.
- SmolLM2 360M Q8_0 added unrelated programming-assistance prose.
- Qwen2.5 1.5B Q4_K_M returned Hello! rather than exactly hello.
- Qwen3 0.6B and 1.7B Q8_0 included think-tagged reasoning before hello. Existing catalog warnings describe this behavior.

Do not change the recorded criterion after seeing output. Normal completion is component compatibility evidence, not general quality, coding/tool ability, iPhone fit, thermal performance, or semantic fidelity. One prompt per model is not a benchmark. No model text was silently stripped or replaced. Source/runtime/model manifests and raw outputs are retained locally. No downloaded files, production behavior, release metadata or catalog were changed.
