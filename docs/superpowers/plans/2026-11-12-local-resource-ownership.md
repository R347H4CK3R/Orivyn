# Exclusive Local Resource Ownership Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. Each native gate runs on the existing free Codemagic connection; no paid billing.

**Goal:** Release cached text-model resources before a separate heavy feature starts, with one owner and no stale presentation.

**Architecture:** Keep one LlamaEngine. Make its existing `unload()` cancel and await its actual worker cleanup. An AppModel-owned lease reserves admission before awaiting that boundary, while a stable image-form presenter retains the lease until real dismissal. Future VM and vision integrate through the same boundary, not a second text engine.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, llama.cpp b9049, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-12-local-resource-ownership.md`

## Global constraints
- No model deletion, new cloud account, paid inference, external computer or simulated completion.
- Preserve draft, attachments, manual provider and persisted conversations.
- Physical iPhone memory/thermal and actual Image Playground remain separate acceptance gates.
- Reserve 1.0.0 for full acceptance; development version stays unchanged.

## Review focus
- Cancellation while the engine is releasing: a late completion never grants a retired lease.
- Backgrounding while a system sheet is open: keep admission blocked until actual dismissal, not only a state flag.
- Regenerate/edit-and-branch/voice: refuse before mutation, including after a history await.
- Repeated acquisition and stale release: exactly one owner, no release of another operation.
- Model load/release/reload: old stream terminates and a new real inference succeeds.

## Task 1: Observe native missing behavior
- [x] Add `LocalResourceReleaseTests` using the real bundled model: consume a token, await `unload()`, require a new stream to succeed and produce nonempty text.
- [x] Add `ImageResourceOwnershipUITests`: open Images → Create, require a truthful released-resource indicator, cancel, and prove the original composer is available without sending.
- [x] Run those tests with repaired staging tests in a focused native gate. Preserve actual failure evidence before production edits.

## Task 2: Engine and coordinator ownership
- [ ] Retain the active engine Task; `unload()` is async, marks release, cancels it and suspends until cleanup nils resources/path and resumes waiters. New streams reject during release.
- [ ] Add `LocalHeavyWorkLease` (UUID, kind, preparing/ready/revoked) and injectable `LocalResourceReleasing` boundary; production uses the shared LlamaEngine.
- [ ] AppModel `beginHeavyWork(id:kind:) async throws`, `endHeavyWork(id:)`, `revokeHeavyWork(id:)` and foreground changes validate cancellation and ownership before/after release. Revocation retains admission until presenter dismissal.
- [ ] Add controlled native coordinator tests for concurrent calls, pre-cancellation, cancel/restart, late release, background, active generation, every submit path, and composer preservation. Fake only the asynchronous resource boundary, never an inference result.

## Task 3: Stable image presenter and lifecycle
- [ ] The explicit Create an image action opens a stable form that prepares a lease before enabling the system sheet, with cancellable progress and accurate ready status. The same admission path is exercised even when simulator capability is absent; no heavyweight system image work is attempted there.
- [ ] Release only on stable outer presentation dismissal, and use exact owner ID. Nonactive phase requests sheet dismissal and revokes new work; do not assume dismissing has already freed Apple's memory.
- [ ] Add memory-warning/serious thermal event handling that cancels current work and requests release without claiming a universal memory ceiling.
- [ ] Run focused unit/UI and real load/release/reload gates, then the complete native candidate before any release. Check exact source, screenshots and package separately.
