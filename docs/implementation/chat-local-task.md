# Chat to local-task review

First increment: explicit review from the composer reuses LocalAgentView. Ordinary Send stays unchanged. Only the typed draft is copied, at most512 UTF-8 bytes; attachments are not silently discarded or read. Navigation never creates/runs a task. The existing plan/checklist approval and explicit Run remain mandatory. Closing keeps the original draft. Read-only local model capabilities, progress, pause/recovery and result records stay in the existing screen.

Not full ChatGPT parity or automatic task execution. No external tools, side effects, network dispatch or model download are added. Conservative direct-request suggestions only highlight a review option, never grant permission. Native UI verification remains required.

Plan: add validator + direct-request suggestion tests; add composer sheet and seeded view initializer; native UI regression for draft preservation/no auto-run; run Foundation and existing test suites; report platform checks separately.

## Verification (this branch)

- The two source-boundary regression checks failed before implementation and pass after.
- Exact production Foundation suite:474 tests passed, including four new request/prefix/UTF-8 validation tests. Linux redirect fixture remains excluded by the existing harness.
- Existing Node agent suite:150 tests passed.
- Python aggregate:271 tests, four failures/four errors/one skip. Failures: attachment tokenizer-aware preparation assertion; explicit-model all-success gate; outdated Settings replacement disclosure assertion; outdated import-picker source assertion. Errors: three explicit-model pipeline fixtures; missing bundled VM guest asset. These are outside this patch's touched behavior and are not claimed repaired.
- Added native UI test `testChatDraftOpensLocalReviewWithoutCreatingOrRunningTask`, not executed here. Native compilation, simulator layout/touch behavior and physical iPhone remain unverified for this change.
- No IPA, catalog entry, remote branch, or release published by this step.
- Independent source review found no blocking issue; reviewer reran the two structural tests and whitespace check. Native keyboard/layout/sheet behavior still needs the simulator gate.

## Follow-on: exact conversational routing

For three explicitly recognized request shapes, Send now opens checklist review instead of asking a text-only provider to pretend to perform the task:
- `List installed models` (optionally `Please` or `my`)
- `Show app information` (optionally `Please` or `the`)
- `Search saved memory for <literal query>` (also `memories`/`my saved memory`)

The composer discloses this routing before Send. Only one read-only operation is proposed, with memory results limited to three. The existing checklist is prefilled, not approved. The user still chooses Review checklist, approves its exact scope, then Run. Opening the sheet performs no model inference or read. Queries remain literal data, never extra commands. Compound model-list requests, how-to questions, negations and unsupported tasks remain ordinary chat. Attachments prevent automatic routing. This supersedes the initial increment's blanket statement that Send is always unchanged; unrecognized conversation remains unchanged.

This is a deterministic capability-aware bridge, not open-ended planning or a reproduced ChatGPT backend. It does not interpret every natural-language paraphrase. Added native Send-route test uses the existing controlled UI provider, not a real-model claim.

Follow-on verification:476 Foundation tests passed (six request tests);150 Node tests passed; Python aggregate remains the same four failures/four errors/one skip across271 tests. Independent review found no blocking issue; suggested capability-copy fixes were applied. Both native bridge UI tests remain pending, not reported as passed.
