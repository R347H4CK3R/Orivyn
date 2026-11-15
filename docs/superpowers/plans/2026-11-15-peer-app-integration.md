# Native Peer App Integration Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prove the tested authenticated exchange compiles inside the real iOS app before app lifecycle wiring.
**Architecture:** Isolated XcodeGen package dependency integration with a compile-only SPI flag. Existing transport and database semantics remain unchanged.
**Tech Stack:** Swift 6, Xcode 26, pinned Apple swift-certificates/SwiftASN1/swift-crypto.
**Spec:** docs/superpowers/specs/2026-11-15-peer-app-integration.md

## Global Constraints
- Free public GitHub macos-15 runners only.
- No pairing consent bypass, network listener startup, IPA packaging or publication.
- Preserve exact pinned dependency revisions from the 24-case native gate.
- Compilation does not establish device runtime, automatic scheduling or complete sync.

## Review Focus
- Device and simulator SDK/API differences: build both exact app targets.
- Unpinned transitive packages: verify all three resolved revisions.
- Feature exclusion hiding errors: set ORIVYN_PEER_TLS_SPIKE in the gate.
- Build failure masking: preserve logs and require both xcodebuild exits to succeed.
- Overclaiming: retain scope and runtimeTests=false in results.

### Task 1: Compile actual app with tested transport dependencies
**Files:** project.yml; scripts/ci_peer_app.sh; .github/workflows/peer-app.yml.
**Interfaces:** existing PeerTLSProbe.AuthenticatedChannel and PeerTextRevisionExchange; no new production API.

- [x] Establish current gap: app project contains no X509/SwiftASN1 dependency and never enables SPI.
- [x] Add exact pinned package dependencies on an isolated branch; enable SPI only in the compile gate.
- [x] Add a bounded build of generic iOS and iOS Simulator and resolved-pin assertions.
- [ ] Run the native gate; repair demonstrated SDK/build failures only.
- [ ] Preserve evidence and review before any main integration.
