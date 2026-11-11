# Jarvis-EVO Implementation Plan

> **For agentic workers:** Use test-first implementation with independent review and verifiable checks.

**Goal:** Deliver a native offline-capable iOS 26+ assistant and a genuinely validated unsigned IPA.

**Architecture:** Native SwiftUI, SQLite persistence, modular asynchronous streaming providers. Local open-weight model first, optional system and explicitly configured remote providers. All release claims are evidence gated.

**Tech Stack:** Swift 6/Xcode 26, SwiftUI, SQLite3, Foundation, AVFoundation/Speech, PDFKit, llama.cpp-compatible local runtime.

**Spec:** ../specs/2026-11-11-jarvis-evo.md

## Global Constraints
- iOS 26+, iPhone 16 Plus, ARM64; separate Jarvis-EVO identity.
- No required subscription or paid API key. No new paid service commitments.
- No fake inference or nonfunctional advertised controls.
- No public release until defined verification passes.

## Review Focus
- Partial/cancelled stream must survive restart without being marked complete.
- Switching conversations while streaming must not attach output to another conversation.
- Import malicious paths/oversized data must not escape sandbox or replace valid history.
- Remote redirects must not leak keys to other hosts.
- Download failures, hash mismatches and memory pressure must not activate broken models.

## Task 1: Durable conversations and provider contracts
- [ ] Tests for create/persist/search/archive/delete, edit branch, import/export rejection and restart recovery.
- [ ] SQLite store plus Codable value types, bounds and transaction semantics.
- [ ] Native XCTest; run full suite before accepting.

## Task 2: Real inference and storage
- [ ] Test SSE parser fragmentation/error/done and remote request policy.
- [ ] Implement selected local runtime, download integrity, storage accounting, cancellation.
- [ ] Test actual model prompt and offline restore; record memory/runtime evidence.

## Task 3: Native interface and iOS services
- [ ] UI tests for navigation, send/stop, editing, copy, history and settings.
- [ ] SwiftUI conversation screen, sidebar/search, model picker, settings; functional attachment and voice controls only.
- [ ] Persistence, file import/export, TTS/dictation, original assets, screenshots.

## Task 4: Build and release diagnostics
- [ ] Failing package-verifier fixtures, then Mach-O/plist/archive checks.
- [ ] CI Xcode 26 test and ARM64 build with logs preserved; equivalent Codemagic fallback.
- [ ] Run full suite and independent review; fix regressions.
- [ ] Gate release/catalog generation on verified IPA, checksum, tests and known limitations.

## Remaining feature milestones
Research/citations, image-capable generation/editing, advanced document formats, embedded sandbox execution, authorized tools and task scheduling, semantic embeddings and optional encrypted sync require their own tested implementations. Track honestly, rather than label unsupported functions complete.
