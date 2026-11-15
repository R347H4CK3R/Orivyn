# Explicit local completion contracts (design, not implemented)

## Goal and boundary
Prevent a newly approved local task from claiming an answer before its explicitly selected operations finish. This does not infer arbitrary user intent, verify prose, or repair legacy generic autonomy. Preserve v1 records and the existing v2 reviewed conversation workflow byte-for-byte in behavior.

## Alternatives and engineering decision
1. Infer required tools from free text: rejected. Negation, quoted instructions, search-only goals, and multiple targets make keyword inference unsafe; an unconstrained model proposal is not consent.
2. Force reads after every search: rejected. This exceeds search-only intent and does not prove the correct message was read.
3. Add an explicitly reviewed checklist with exact arguments: recommended. Initial scope is deliberately smaller than general autonomy and independently enforceable.

## First deliverable
A new version 3 task stores `completionContract: {schema:1, steps:[{name,arguments}]}` with one to three ordered steps. Initially permit only `get_app_info`, `list_models`, and `search_memory` with an exact user-entered nonempty bounded query and limit. User selects these in a composer, reviews all operations and arguments, then approves; Run remains a separate action. No model proposal, execution, or memory access occurs while composing. Unknown fields, duplicate operations, malformed arguments, and unsupported tools fail closed.

Conversation tools remain exclusively on the current reviewed v2 path; do not implement cross-task dependencies or widen conversation access. Arithmetic is also excluded initially: its existing native dispatcher binds an expression to the whole trusted goal, so multi-operation arithmetic would require a separately reviewed expression-consent design. Nothing changes that guard.

## Enforcement
- Separate strict Swift contract parser and native policy plus JS reducer contract validation. Never treat a model-selected tool as authorization.
- Next allowed operation is exactly the next checklist item. Reject reordered calls, changed arguments, extra calls, premature answers, and forged successful history. Only answer after each required result is successfully recorded and available in bounded prompt evidence.
- Native dispatch independently checks exact contract action before touching app data. Grammar exposes only the exact next operation or final answer; grammar is assistance, not authority.
- Retain current limits, save-before-dispatch, cancellation, interrupted marker/recovery, archive and restore behavior. Test crash/restart at each operation boundary; no automatic resume.
- Results are untrusted data. Completion means the approved calls finished, not that all possible memories/models were enumerated or that answer text is accurate. Preserve truncation/search-window warnings. A successful empty memory search is a completed search, not proof that no memory exists outside the window.
- If bounded prompt cannot carry required evidence, fail explicitly rather than dropping earlier results or changing the checklist. No read-result widening or silently truncating proof.
- Do not recompute volatile model/memory sources at answer time as if they were an immutable snapshot; persist point-in-time results and show that scope. Validate provenance at dispatch/store boundary; local unsigned files are not tamper-proof security storage.

## Compatibility and UX
Use a distinct optional snapshot field only for v3; v1/v2 never migrate automatically. Existing conversation plan creation, approval, title matching, paginated reads, native transcript and tests remain unchanged. Current generic task remains experimental, including its failing native acceptance evidence. New UI must say approved operations completed, not goal verified. No production release until independent review and actual portable/native checks; no claim of device verification.

## Implementation sequence and proof
1. Red reducer tests: parser rejection, zero/one/three-step sequences, wrong order/arguments, failed/interrupted result, premature/extra answer, bounded evidence and legacy v1/v2 controls.
2. Implement isolated JS v3 contract/policy and strict snapshot support; regression run existing Node suite.
3. Matching Swift parser/policy tests with shared adversarial vectors; bind native request/dispatch and explicit approval state. Verify fake model cannot skip second step.
4. Composer and approval UI with review/cancel/provider-switch/navigation guards; native typecheck and targeted simulator workflow.
5. Real local-model test uses two different approved operations and asserts two actual successful dispatches before answer, with exact evidence capture. Do not substitute mocked inference for this gate.
6. Independent integration review and preview decision only after evidence; preserve build14 and all older previews.

## Current status
Design re-review approved isolated reducer implementation. Task 1 is under independent code review; no native bridge or UI integration exists yet. Existing `LocalReadWorkflowPolicy` and reviewed grammar are conversation-specific; reuse their pattern, not their types or allowlists. Keeping those paths separate minimizes regression risk.

## Review resolutions (2026-11-15)
- Authenticity: reject structurally invalid histories and inconsistent transitions, not structurally valid fabricated on-disk JSON. No signed-history/authenticity claim.
- Interruption: fail closed. Recovery preserves running as interrupted without execution. Explicit Resume settles the uncertain step as interrupted and fails the v3 task with retained evidence; user creates a new approved checklist. A ready task with a fully persisted successful result resumes from the next exact step. No repeated calls are automatic.
- Strict dispatch: expose task version in native snapshot and switch explicitly on 1/2/3. v3 requires its valid contract and approvalRevision=0; otherwise throw before provider/tool invocation. Never generic fallback. Draft approval binds immutable goal/contract and selected provider identity. Editing composer, cancel/discard, navigation-away, or provider mismatch invalidates it. Stored approval is scope metadata, not cryptographic attestation.
- Duplicates: disallow duplicate tool names, even different queries; one memory search maximum in this initial version. One to three steps. Schema exactly 1; approvalRevision exactly 0; contract immutable after creation. Goal existing 512 UTF-8 bytes. Query 1–256 UTF-8 bytes, non-whitespace, valid Unicode without unpaired surrogate or C0 controls except tab/LF/CR; no normalization or case folding. Limit integer 1–10. Unknown fields fail closed.
- Results: require strict JSON objects <=4096 UTF-8 bytes, reject duplicate/prototype keys and unknown fields. Mandatory exact fields match existing LocalReadTools. Optional `resultTruncated:true, omittedItems:N` must occur together, N positive integer; absence means no budget omissions. No `false`/zero omission pair.
  - app info: app/assistant/repository/repositoryAccess strings (each <=1024 bytes), capabilities array whose count plus omittedItems is at most24 of exact id/status objects (id <=256 bytes, status one of available/conditional/notAvailable). Metadata strings do not authorize actions or imply source access.
  - models: models array max10 of exact id/name strings (each <=4096 UTF-8 bytes within the total result budget; existing 96-Character prefixes may contain multi-scalar graphemes); totalInstalled nonnegative integer >= array count plus omittedItems; truncated boolean exactly reflects totalInstalled >10. Array count plus omittedItems must equal min(totalInstalled,10).
  - memory: memories array max approved limit of exact id/excerpt/excerptMayBeTruncated (UUID, <=160-byte excerpt, boolean); totalMatchesInWindow nonnegative integer >= array count plus omissions; searchedMemories integer0–500 >= totalMatchesInWindow; resultsLimited boolean equals totalMatchesInWindow > approved limit; searchLimited boolean and, if true, searchedMemories=500. Omission count plus array count equals min(totalMatchesInWindow, approved limit). UUIDs unique. Empty matches remain a valid completed bounded search.
- Failure record validation: failed/cancelled/interrupted history may be loaded with exact approved step identities/order and null result for non-success; it cannot authorize a next operation or answer. A pending exact operation can be preserved across recovery but not replayed after uncertainty. All successful entries validate result schema in both runtimes.
- Tests explicitly cover restart before dispatch (ready/no call), after dispatch before recording (interrupted then failed), after saved result (next approved step); no hidden operation or inferred permission.

## Baseline provenance issue
The build14-derived tree lacks earlier separately reviewed commit 67a9a18 (access-boundary wording). This omission predates this feature. Integrate that exact reviewed correction separately after baseline/test review; do not silently include it in the completion contract diff or falsely claim current visibility.
