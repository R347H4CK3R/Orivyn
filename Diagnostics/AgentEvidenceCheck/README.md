# Missing-evidence decision experiment

Hypothesis: a short explicit missing-evidence field before the decision may reduce premature answers from the pinned Qwen3-1.7B Q4 model. This is an isolated diagnostic, not a production change or a replacement acceptance gate.

Compare baseline with one structured evidence-check variant across the two prior synthetic fixtures plus frozen Cedar and Juniper holdouts, requiring third/fourth-message reads. Both variants retain identical model, 2048 context, 384 output tokens, temperature zero and per-case 180-second bound. The unchanged decision grammar is nested under the experimental wrapper; returned conversation IDs remain constrained to each actual fixture.

Success criterion for an individual decision is exactly read_conversation with the returned ID, requested message index and offset zero. A read_result is recorded but does not count as the target read. No tool executes. Raw outputs, prompts, grammar, binary/model hashes, failures and summaries are retained. Workflow success means eight valid diagnostic observations, not successful autonomy; inspect targetReadChosen counts. No prompts or model settings are integrated unless later full workflow and independent regressions pass.
