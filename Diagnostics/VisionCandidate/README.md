# Alternative model diagnostic; not an application change

Prior SmolVLM2 prompt/caption experiments did not resolve both failures without regressions. This evaluates Qwen3-VL-2B-Instruct Q8 with the existing bridge, unchanged 2048-context/128-output limits, and all ten frozen QualityV1 images, questions and answer criteria. It tests a model change instead of another prompt tweak.

The pair is pinned to [ggml-org commit ea6a110](https://huggingface.co/ggml-org/Qwen3-VL-2B-Instruct-GGUF/commit/ea6a11058182570be6436b9a2e4ee7f7b49f908d), whose LFS pointers provide exact sizes and SHA-256 values. Model 1,834,427,296 bytes; projector 445,053,056 bytes. These are downloads, not process-memory estimates or device fitness claims.

Pixels are processed by local CPU inference on an ephemeral public GitHub Linux runner. Only generated synthetic fixtures are used. No personal images are sent to a provider. There are no inference API keys, paid services or app consent changes.

Fresh bridge source and binary hashes are retained. Unsupported architecture, resource limits, loading failures, incomplete outputs and wrong answers remain failures. No default model change or iOS/device acceptance follows from this experiment; broad vision requires independent images and native memory/runtime tests even if all ten cases pass.
