# Chat-bound local task evidence

Baseline: 42b442b. This is an incremental conversational task surface, not general autonomous remote execution.

## Implemented
- Saved chat exposes explicit Plan a saved-conversation task for a nonempty <=512-byte draft without attachments and an available local model. This tap starts proposal inference only; search/read execution still requires reviewed scope approval and Run.
- Chat proposal defaults to conversation search; exact title/message-number reads are selectable in the existing review. No inferred broad authority, attachments, remote model or plugin calls.
- Immutable origin and exact reducer bytes are stored in one atomic envelope; preparation alone is not persisted. Incomplete envelopes and symlink task files fail closed. No migration or deletion of legacy tasks.
- Conversation cards read durable records, refresh every 30 seconds or manually, show actual recorded stage, operation evidence and separately labeled unverified model answer. Cards are not hidden messages and are not sent as chat-model context. Draft and attachments are untouched.
- Origin conversation plus ephemeral conversation/provider revisions bind approval and running work; provider replacement and selection round trips invalidate pending work. Reopening a task is explicit and rebinds ephemeral review context to the same durable origin.
- Existing LocalAgent reducer recovery resumes interrupted tasks without intentionally replaying completed reads. No action runs on loading or displaying a card.

## Verified locally
- Missing-context and missing-origin API failures observed before implementation.
- Final exact-source Foundation run: 558 tests, 0 failures. Linux-only URLProtocol redirect exclusion unchanged; Apple fixture remains required. Compiler reports existing test warnings; this is not a warning-free build claim.
- Swift frontend syntax parse and git diff --check pass. This is not Apple SwiftUI typechecking.
- Python suite: 271 tests,4 failures,4 errors,1 skip, reproduced on untouched42b442b. Existing failing tests: attachment fitting tokenizer preparation; explicit-model-gates all-success plus three pipeline errors; persistence import disclosure; UI Files cancellation source contract; bundled guest allowlist error. No baseline fixes attempted.

The card scan uses the existing MainActor store, bounded to 100 active records, each raw record <=131,072 bytes and a bound envelope <=263,000 bytes. It skips scans while shared heavy work is active. At the maximum library size, synchronous disk reads can still cause UI latency; off-main snapshot loading remains a performance follow-up, not a verified improvement.

Independent review found and fixed a missing-sidecar fail-open before commit. The atomic-envelope regression failed against the former implementation, then passed after replacement. The reviewer rechecked the correction with no blocking finding.

## Native tests authored, NOT executed locally
ChatLocalAgentSessionTests:
1. testChatOriginSurvivesReloadAndCrossConversationCannotRun
2. testChatApprovalRejectsProviderRoundTrip
3. testChatSelectionRoundTripDuringDecisionCannotDispatch
4. testChatResumeRetainsCompletedEvidenceWithoutReplayingFirstRead

Synthetic model-output injection only, not production model quality proof. Actual SwiftUI layout, lifecycle, local model proposal quality, on-device persistence and device installation require native verification. No CI dispatched, no IPA or release published by this change.

Combined integration (with separate plugin approval oracle) passed 560 portable
XCTest cases (the separate Swift Testing runner contains zero tests). Independent
selector audit counts 135 required native/simulator tests for the next synthetic
gate. Scripted local-task boundaries are not real-model task/UI/device acceptance.
No release is authorized by portable tests alone.
