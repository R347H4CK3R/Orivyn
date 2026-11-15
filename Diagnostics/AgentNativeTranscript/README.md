# Native tool transcript comparison

The Q4 and Q8 flat-prompt baselines both chose zero of four required message reads. The explicit missing-evidence wrapper chose one of four and is rejected. Test the different hypothesis that the custom flat transcript is mismatched to the model's trained tool-call format.

Render the tokenizer.chat_template extracted from the exact verified Q4 GGUF using pinned Jinja2. Supply all seven existing read-only tool schemas and the actual completed search as assistant/tool messages. Do not force a tool call with grammar in that arm: answers and malformed calls remain failures. Compare the existing flat prompt on the same four fixtures and model.

This is a format/protocol comparison, not a single-variable ablation. Both arms use a 4096 context and 384 output budget; current production context is 2048, so any improvement requires later context/memory validation. No tool executes and no app/tool permission changes. Persist the template/hash, rendered prompts, raw outputs, failures and exact target-read scores. Workflow success means eight valid observations, not autonomy completion.
