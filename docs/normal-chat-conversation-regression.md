# Normal-chat conversation regression investigation (2026-11-17)

## Observed report

Owner confirmed Orivyn 0.1.2 and multiple models. Supplied conversation repeats a refusal to draft a simple Python script, loses the referent of “Explain”, shows `<think>` output, and includes failed/incomplete replies. A get_app_info app-recorded receipt proves at least that turn used the bounded normal local-agent route. No inference about which model generated each individual reply is possible from the pasted transcript.

## Source findings

- AppModel builds a general assistance policy, metadata and Behavior prompt, but NormalChatLocalCursor intentionally does not forward that caller system prompt, to avoid inheriting arbitrary tool authority. Its separate agent prompt previously did not explicitly distinguish writing text code from executing/building it. This divergence is verified; its causal contribution to a particular sampled refusal remains an inference.
- Normal-loop history was the last six messages, each capped at its first512 UTF-8 bytes, including failed messages. Direct LocalPromptBuilder already excludes failed messages. The current question appeared twice, once in history and again as currentUserRequest.
- Model changes do not erase stored assistant history. Earlier mistaken refusals can therefore remain in the next model's input. This is not evidence of cross-model cache corruption.
- Local LlamaEngine has2048 context tokens and reserves1024 output tokens. Normal-loop instructions/history/read results are packed into one user message. Unlike direct chat's independent historical messages, its context subfields cannot be removed by LocalPromptBuilder's whole-message trimming. Large inputs/results may fail promptTooLong. This is a separate unresolved budget issue, not fixed by this patch.
- ChatAnswerStream strips only leading exact reasoning blocks; handling later blocks is being investigated separately. This patch does not modify it.

## Narrow changes

1. Trusted normal-loop guidance distinguishes code drafting from execution, instructs the model not to treat old refusals as capability policy, and preserves the conversational meaning of short follow-ups. It still does not inherit caller system strings or historical execution authority.
2. Exclude failed history and avoid duplicating the current user request. Stored conversation records are not altered.
3. Add captured-request tests and native pinned-model probes for the owner's generic Python request, fresh and after the supplied prior-refusal excerpt. Also add the prior-refusal case to the direct-provider gate. These are deliberately bounded excerpts, not an exact full-conversation replay or a cross-model reliability claim.

## Evidence and limitations

Captured-request tests: guidance regression produced3 failures before change; history regression produced2 failures before change. Final Foundation-only suite:616 passed, zero failures. These execute production routing with a deterministic provider fixture; they do not establish model answer quality.

Native probes require the existing simulator fixture/ORIVYN_REQUIRE_NORMAL_CHAT_MODEL and ORIVYN_REQUIRE_CONVERSATION_MODEL gates. They have not been run in this Linux checkout. No IPA built, no branch uploaded, no release published. Actual-model tests may expose additional context-budget or answer-quality failures; do not weaken the expectations merely to publish.

Main Python suite (`scripts/tests`):297 tests passed,1 skipped. An additional top-level `scripts` discovery found two pre-existing backup-host expectation mismatches (source count30 vs28; test count164 vs152) and missing `jinja2` for native transcript import. Those checks are not green and were not modified here.
