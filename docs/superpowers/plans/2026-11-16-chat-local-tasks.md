# Chat-bound Local Tasks Implementation Plan

> **For agentic workers:** Execute task-by-task with synthetic tests and independent review.

**Goal:** Durable local task review, evidence and explicit continuation in originating chat.
**Architecture:** Existing LocalAgentSession/reducer; atomic envelope origin; reusable chat card. No remote operations.
**Tech Stack:** Swift, SwiftUI, Foundation, existing JavaScriptCore reducer.
**Spec:** ../specs/2026-11-16-chat-local-tasks-design.md

## Constraints and review focus
Preserve legacy tasks, composer/attachments and originals. Fail closed on damaged links, cross-chat changes, provider ABA, deletion, storage failure. Resume must not replay completed steps; no automatic execution from tool results. Native tests require Apple runtime and remain unverified locally.

- [x] Add failing Foundation tests for immutable origin/reload/corruption and ephemeral context binding; observe failure.
- [x] Implement bounded protected LocalAgentStore origin envelope and context value. Run tests.
- [x] Bind LocalAgentSession planning, approval, selection and Run to origin/revisions; persist origin before task record. Add synthetic native lifecycle tests.
- [x] Add reusable chat task cards and review sheet using existing panel; retain explicit approval/Run; no composer mutation.
- [x] Run Foundation and Python suites, parse Swift, document exact limitations and independently review before commit. No CI dispatch/release.
