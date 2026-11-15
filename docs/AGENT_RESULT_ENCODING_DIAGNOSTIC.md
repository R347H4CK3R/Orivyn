# Nested tool-result encoding — completed diagnostic

[Run 43667390789](https://github.com/R347H4CK3R/Orivyn/actions/runs/43667390789) at 2266d32 collected four valid JSON decisions from the pinned Qwen3-1.7B Q4 model using the non-conversational completion executable.

Neither arm performed the required conversation read:
- Orchid baseline: answered that the code is in the second message.
- Orchid decoded result: answered that the code is in the second message.
- Maple baseline: incorrectly presented the conversation UUID suffix as the code.
- Maple decoded result: answered that the code is in the second message.

The encoding hypothesis is rejected for these fixtures. Decoding alone did not fix premature answers. No production prompt, model, permissions or acceptance gate was changed. This is only one decision after synthetic search output; it is not a full workflow evaluation or a device test.

Earlier attempts provide no accuracy evidence: local processes exited 137, the conversational CLI timed out, an intermediate completion invocation used an incompatible CLI-only flag, and --log-disable suppressed generated token output. The final harness uses llama-completion, preserves JSON escapes, captures token output, and rejects missing/malformed decisions despite a zero process exit. Full raw observations and hashes are retained in the adjacent evidence file.
