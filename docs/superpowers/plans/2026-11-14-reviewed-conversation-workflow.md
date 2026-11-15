# Reviewed Conversation Workflow Implementation Plan

> For agentic workers: use the existing delegated implementer and independent reviewer; execute task-by-task with red-green evidence.

**Goal:** Enforce approved multi-step conversation reads before accepting a model answer.
**Architecture:** A local model drafts a typed plan; explicit review creates a durable contract. Reducer policy, generated grammar and native dispatch independently enforce allowed dependencies and completion.
**Tech Stack:** Existing Swift/SwiftUI, JavaScriptCore reducer, llama.cpp and portable Swift/Node harnesses.
**Spec:** ../specs/2026-11-14-reviewed-conversation-workflow-design.md

## Global Constraints
- Six external calls;3500-byte complete context; no remote operations or automatic runs.
- Exact plan fields and bounds from spec; preserve version1 task behavior.
- No weakening existing acceptance; no injected model decisions or hidden fixture-specific rules.

## Review Focus
- Wrong/ambiguous model proposal must remain unapproved.
- Search-only approval must never permit message reads.
- Deleted/changed message, skipped page or wrong ID cannot satisfy prerequisites.
- Crash/cancellation must not replay uncertain calls or lose consent scope.
- Stored instruction text cannot alter tools, plan or completion requirements.

## Task1: Typed draft and durable contract (implementation worker)
Files: new Core/LocalReadPlan.swift and tests; Core/AIProvider.swift; local engine plan grammar; Resources/LocalAgentCore.js; Core/LocalAgentSnapshot.swift; Services/LocalAgentCore.swift.
- [ ] Add failing tests for plan validation, version1 compatibility, exact scoped search and premature answer rejection.
- [ ] Implement typed proposal parsing and versioned approved contract creation; preserve original goal.
- [ ] Derive permitted tool intents and completion from actual dependency-linked results, including pagination/source identity.
- [ ] Add malformed/ambiguous/no-hit/mutation/recovery tests; run complete reducer and Foundation suites.

## Task2: Production session and permission boundary (implementation worker)
Files: Services/LocalAgentSession.swift; Core/LocalAgentGrammar.swift; Providers/Local/LlamaEngine.swift; Tests/LocalReadPlanSessionTests.swift.
Interfaces exposed to UI: proposedReadPlan (goal+plan), prepareReadPlan(goal:kind:), approveReadPlan(), discardReadPlan(); existing run remains explicit. Expose concise human-readable scope through typed plan.
- [ ] Add failing no-tool-before-approval, stale draft, selected model/lease, unsupported provider and no-read-for-search-only tests.
- [ ] Implement local plan-only inference and approved task creation; maintain durable-before-dispatch and native policy validation.
- [ ] Mirror policy in grammar; validate actual generated grammar rejection and positive cases.

## Task3: In-app review (root)
Files: UI/LocalAgentView.swift; additive native/UI tests as feasible.
- [ ] Show explicit Search only/Read messages kind selection, separate drafting action and exact draft goal/query/title/message numbers.
- [ ] Explicitly approve/create or discard; prevent running draft without approval; show stored contract and completion evidence without asserting prose accuracy.
- [ ] Preserve existing experimental task and all current assertions.

## Task4: Actual evaluation (independent evaluator plus implementer)
Files: existing production smoke harness and new isolated holdout fixture driver; additive ProductionLocalAgentSessionTests gate.
- [ ] Keep old generic workflow results; run new reviewed workflow separately with actual model-generated proposals and decisions.
- [ ] Freeze product implementation before revealing independent fixtures; one real model worker at a time.
- [ ] Preserve every attempt and report contract completion, semantic answer quality and safe refusal separately.
- [ ] Review integrated changes, run affected portable checks, commit and update draft PR; retain Apple and physical-device gaps.

## Integration status
Backend and review UI implemented; integrated portable results: 423 Foundation checks, 134 agent checks, 39 VM checks, and 201 Python checks (one skip). See docs/evidence/reviewed-read-workflows-20261114/INTEGRATED-PORTABLE.json. SwiftUI syntax parsed; Apple SDK typecheck/runtime not run for this UI. Search consent text explicitly discloses message and attachment excerpts. Independent real-model holdouts remain a separate capability gate; passing portable checks does not establish model reliability.
