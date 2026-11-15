# Reviewed local conversation workflows

This is a separate, opt-in path; the existing experimental task and its failing real-model acceptance gate remain unchanged. The user selects conversation read or search-only mode before drafting. That choice is user intent, not successful model classification. A selected local model proposes the query, exact title and message indexes; the user must inspect and approve that exact proposal to create a task. Run is a separate action. Drafting supplies only the goal and workflow kind, and does not read saved messages. A different goal/scope requires a new proposal and approval.

`LocalReadPlan` schema1 allows exact fields only, bounded query/title, and one to three unique zero-based message indexes for reads. `LocalReadPlanProposal` contains the immutable original goal and typed plan. Session APIs are `prepareReadPlan(goal:kind:)`, `approveReadPlan()`, `discardReadPlan()`, `proposedReadPlan`, and `isPreparingReadPlan`. Draft work has separate cancellation handling; parse errors, cancellation and stale provider selection preserve the previously selected task. An outstanding proposal blocks running a previous task.

Approved tasks use version2 with `readPlan` and approvalRevision0. This records approval scope; it is not a cryptographic consent certificate. Version1 remains supported without retrospective validation claims. The reducer derives allowed actions from the contract and completed results. A read contract permits the exact approved query with limit10, then only the uniquely resolved title and approved message indexes at contiguous offsets. Search-only never permits message reads. Interrupted uncertain contracted calls fail on resume instead of replaying. Missing, ambiguous, incomplete, changed, oversized or corrupt evidence fails without an answer. Forged answered states cannot bypass prerequisites or simultaneous context limits.

Search titles in ordinary results are clipped. Reviewed searches therefore add native `approvedTitleMatchIDs`, derived from actual returned IDs and current full NFC-normalized, lowercase titles. The reducer requires a unique candidate present exactly once among returned matches. Native policy independently recreates the entire bounded search result from current source and compares it before subsequent actions and final answer, covering search-only results too. Before reads/answers it recreates every stored raw message page, comparing ID, role, state, cursor, text, metadata and next cursor; completed pages concatenate to the full current message. Current exact title must remain uniquely bound to the selected ID. No fuzzy prefix/diacritic matching selects targets.

The proposal grammar fixes only the user-selected kind. Reviewed execution grammar permits only the derived actions, or an answer after every prerequisite is complete. Request modes are mutually exclusive at the engine boundary. Reducer and native checks remain authoritative even with a malicious or nonconforming provider. Six external calls and 3500 bytes of complete simultaneous evidence are unchanged; no result is dropped to fit. Final prose remains model-generated and unverified.

## Initial implementation portable results

- 134 JavaScript tests; version1 compatibility and reviewed contract, Unicode paging, immutable scope, budget, interruption and forged terminal state checks.
- 423 Foundation XCTest checks, including strict proposal parsing, conflicting request modes, exact long-title prefix collisions, current-search corruption/mutation, native contiguous Unicode pages and changed-source rejection. The existing Linux URLProtocol redirect exclusion remains.
- 198 Python checks, one existing tokenizer-dependent skip.
- 46 native b9049 grammar acceptance/rejection cases covering zero/one/multiple IDs, fixed user kinds, premature answers, exact allowed actions, slash/quote/backslash/Unicode/newline literals. No model is loaded for grammar tests.
- Actual production LocalAgentSession typechecked and executed in a Linux host ownership harness with Node/AppModel/provider unit scaffolds, using the installed Swift static standard library. Draft/teardown cancellation, parse failure, wrong-kind proposal, stale provider, immutable approval, draft/Run separation and zero source reads before explicit Run passed. Initial dynamic Observation linking failed with the known missing runtime symbol; the failure is retained. No replacement runtime symbol or production source transformation was used. Apple JavaScriptCore, Observation UI behavior and device performance remain unverified here.

## Actual model evidence and remaining blockers

Five sequential development runs used the pinned Qwen3 1.7B Q4 model and actual production engine/proposal grammar, 384 output tokens and temperature0. Three mixed-kind attempts proposed search-only for a requested read and were rejected. The subsequent explicit user-read mode attempts retained the unchanged Orchid notebook/Maple journal goals and exact approval/answer checks. Orchid proposed a wrong title and indexes[1,2]; Maple proposed an expanded wrong title and indexes[1,2]. Both were rejected before task approval or tools. No query/title/index was repaired or injected. **Zero of these five runs completed the reviewed workflow or demonstrated answer accuracy.** These are safe proposal rejections, not successful model refusals or autonomous completions.

The existing host goals still require finding the saved title, reading its second message, and reporting the exact synthetic verification code. All attempts, source/model manifests and raw proposals are preserved under `docs/evidence/reviewed-read-workflows-20261114/`. Independent frozen holdouts and additive real iOS session acceptance are separate gates, not replaced by these unit tests. Automatic sync, broad vision quality, general autonomy, iPhone installation/performance, and 1.0.0 completion remain unfinished or unverified. No remote publication was performed by this worker.

Model proposals use `messageNumbers`, an array of one to three unique one-based
integers from 1 through 10000. `LocalReadPlan.parseProposal` strictly validates
that representation and subtracts one from each supplied number to produce the
existing durable schema-1 `messageIndexes`. Stored plans, explicit approval, the
reducer, and tool scope remain zero-based and unchanged. The conversion neither
infers intent from the goal nor adds, removes, defaults, or repairs requested
messages. Unknown fields and proposals using the internal index field fail.
Search-only proposals retain their existing schema. Raw model evidence remains
in its original representation; semantic checks compare the converted scope.

Portable validation of this boundary does not establish model proposal quality
or iOS acceptance. Existing model evidence predates this representation and is
not reclassified as a pass; new real-model evaluations remain required.

The additive native reviewed-plan fixture now requests “message number 1” instead of “message index 0”, matching the user-facing proposal representation while targeting the same first stored message. Its search, read, exact random-marker answer, persistence and cleanup assertions remain unchanged. The four earlier native model gates and their goals remain unchanged. This wording change is not evidence of a native pass or a comparison against the prior prompt.

Later controlled comparisons are retained in docs/evidence/reviewed-proposal-comparisons-20261114: the clarified zero-based prompt completed both search-only cases, correctly stopped a missing target, and performed one real authorized read whose extra answer wording failed exact acceptance. Five other read proposals chose incorrect indexes. The larger 4B model diagnostic remained outside product admission and stopped with three cases unrun under its memory guard. These results are not reclassified by the new number representation.
