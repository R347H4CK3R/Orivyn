# Vision precision experiment

Only the SmolVLM2-2.2B language-model quantization changes from Q4_K_M to Q8_0. Preserve the exact production f16 projector, repository revision, pinned llama.cpp source, bridge, frozen ten cases, prompts, context/output limits and scorer. No special case preprocessing or acceptance changes.

Pinned upstream raw pointer: https://huggingface.co/ggml-org/SmolVLM2-2.2B-Instruct-GGUF/raw/1bc3c9f74ceafd4c8d4411cc9cf188bba3798f91/SmolVLM2-2.2B-Instruct-Q8_0.gguf
Model: 1,927,933,984 bytes; SHA-256 c850ffa51b0708be8911766e1d35e8e71365e987c8efb2513a7f237baade074f.

Hypothesis: reduced language-model quantization error may affect the baseline direction/count mistakes without the architecture regressions seen with Qwen3-VL. This is not evidence that quantization caused those errors.

Run all ten frozen cases; keep every failure. Historical Q4 baseline is 8/10. Even a 10/10 synthetic result would need independent holdouts and iOS memory/runtime acceptance before catalog or shipping model changes. Increased model bytes and working memory are tradeoffs, not validated device feasibility. No user images, remote inference, production model selection changes or release publication.
