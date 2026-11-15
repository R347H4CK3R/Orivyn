# Explicit completion contract implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement task-by-task.

**Goal:** Require all explicitly approved local operations before accepting an answer.
**Architecture:** Add isolated v3 contract and independent JS/Swift policies; preserve v1/v2. Compose manually, approve then Run; no inference grants consent.
**Tech Stack:** JavaScript reducer, Swift Foundation/SwiftUI, Node tests, XCTest.
**Spec:** `docs/superpowers/specs/2026-11-15-explicit-completion-contract-design.md`

## Global constraints
1–3 ordered distinct operations, only app info/model list/memory search. No conversation tools or arithmetic. No automatic migration/resume. Existing 3500-byte context, 4096-byte result, six-call limits stay. No release until review and verification.

## Review focus
- Cancelled/failed/interrupted histories must remain loadable without gaining answer authority.
- Stored pending call must match the exact next approved step, even on recovery.
- Unknown/prototype/duplicate fields must fail at the same boundaries in both runtimes.
- Large result must fail with retained evidence, not silently erase early results.
- UI navigation/provider changes must discard stale proposals without creating a task.

## Task 1: reducer contract (independently reviewable, no UI access)
Files: `JarvisEVO/Resources/LocalAgentCore.js`, `scripts/agent-tests/completion-contract.test.cjs`.
Interfaces: `createContract(JSON{goal,id,contract}) -> stateJSON`; `completionPolicy(stateJSON) -> JSON{actions,canAnswer}`. v3 state has completionContract and approvalRevision=0, no readPlan.
- [x] Write behavioral tests for schema bounds, ordered 1/3 step execution, first-result premature answer, unsupported/extra/reordered calls, altered args, forged pending and terminal state, interruption/cancel/fail recovery, adversarial result text, context overflow.
- [x] Run `node --test scripts/agent-tests/completion-contract.test.cjs`, record expected missing-feature failures.
- [x] Implement parser, policy and lifecycle integration. Contract shape validates all retained histories and pending calls; terminal cancellation/interruption retained while only successful complete histories admit answer. No result text becomes authority.
- [x] Run `node --test scripts/agent-tests/*.test.cjs`; review diff and obtain independent code review before commit. 149 passed, reviewer independently reran. Full Python retains baseline4failures4errors1skip.

## Task 2: independent Swift policy and native session
Create `JarvisEVO/Core/LocalCompletionContract.swift`, `Tests/LocalCompletionContractTests.swift`; modify snapshot, grammar, GenerationRequest, LocalAgentSession, LocalAgentCore bridge allowlist, project test target as necessary. The bridge allowlist stays unchanged through Task 1, so normal app creation cannot create v3 before native enforcement exists. Saved v3 files can still enter recover; therefore this reducer-only branch must never integrate/release until explicit version routing and native enforcement land.
Interfaces: strict Codable contract using MCPJSONValue; `derive(history:)` returns exact next operation or completion; independent `validate(intent:)`. Add optional snapshot completionContract. Explicit prepare/approve/discard contract session operations, bind provider identity.
- [ ] Red Swift parser/policy tests matching Task1 adversarial vectors, including pending and non-success histories.
- [ ] Implement strict parser and independent native policy; run portable host tests.
- [ ] Add fake-provider session regression: first answer rejected, exactly two required operations allowed, second result required, stale approval/cancel cannot dispatch. Then integrate exact constrained grammar and independent pre-dispatch/final-answer checks. Do not use native conversation transcript adapter for v3.
- [ ] Run native compile-only gate and tests after independent review; do not claim runtime from typecheck.

## Task 3: user-reviewed composer
Modify LocalAgentView, add UI regression tests with synthetic private app state only.
- [ ] Red tests select two operations, edit exact memory query, inspect review, cancel with no task/data read, approve with no dispatch, Run explicitly, relaunch preserves no-auto-run.
- [ ] Add distinct composer/review; never reinterpret existing v1 goal or interfere with conversation drafting. Display completed operations versus unverified answer and partial-result warnings.
- [ ] Execute targeted simulator workflow after independent review; retain any failure evidence.

## Task 4: real inference and integration evidence
- [ ] Add bounded real local-model test requiring two different approved calls; assert actual native dispatch history and no accepted premature answer. Preserve failing generic v1 test unchanged.
- [ ] Run existing regressions plus one native inference gate; document passed/failed/skipped scope exactly.
- [ ] Independent full integration review; parent decides preview publication only after own packaging and coordinated catalog checks. Preserve build14.
