# iPhone Reference Fidelity Implementation Plan

> For agentic workers: execute natively in this assigned subagent. Required workflow: superpowers:executing-plans and test-driven-development.

**Goal:** Correct the existing app's layout against actually viewed current official iPhone assets without breaking real controls.
**Architecture:** Keep AppModel/services unchanged. RootView owns navigation/drawer/composer; HistoryView becomes drawer contents with explicit close/settings/models callbacks; MessageRow removes redundant assistant chrome; semantic colors stay in JarvisEVOApp.
**Tech Stack:** Swift 6, SwiftUI, iOS 26, XCTest.
**Spec:** docs/superpowers/specs/2026-11-11-ios-reference-fidelity.md

## Global Constraints
- Keep Jarvis-EVO name/original icon; do not impersonate OpenAI.
- No placeholder/fake functional controls. No backend/provider changes in this task.
- Preserve existing accessibility identifiers except documented navigation route changes.
- No local git reset/checkout/commit: parent coordinates connector-based PR commits in the shared unborn checkout.
- Native macOS gates are run by parent; this Linux environment cannot execute iOS UI tests.

## Review Focus
- Long draft and largest accessibility fonts must not cover send/attach/dictation controls.
- Dismissing sidebar must preserve unsent draft; selecting another conversation intentionally clears it per existing model contract.
- Sidebar/settings navigation must return to a usable composer.
- At-rest compact composer cannot become a second-row oversized panel.
- Unsupported voice conversation must not be advertised by a waveform button.

## Task 1: Capture regressions and public evidence
- [ ] Add separate JarvisEVOVisualUITests for horizontal composer geometry, left drawer geometry and dismissal preserving draft, sidebar settings, new-chat functionality and light/dark screenshots.
- [ ] Run native tests-only baseline if Mac lane available; otherwise explicitly document native RED blocker and measure existing real screenshot against public composer bounds.

## Task 2: Correct navigation and conversation surfaces
- [ ] RootView: native monochrome menu/model/new/more toolbar, minimal centered welcome/chips, single-row expanding composer, left drawer and edge gestures with reduced-motion handling.
- [ ] HistoryView: callbacks onClose/onSettings/onModels, plain searchable conversation list, functional horizontal shortcuts, footer Settings. Preserve edit/archive/delete/share behavior.
- [ ] MessageRow: plain assistant content without repeated name/logo; user bubble geometry/color and compact functional action row.
- [ ] JarvisEVOApp: semantic neutral chrome and adaptive blue user-bubble palette. Keep original mark in settings/sidebar only.

## Task 3: Verify the real application
- [ ] Parent combines scoped UI changes with sibling production/test changes and runs scripts/ci_macos.sh.
- [ ] Inspect native captures (empty light/dark, sidebar, long draft/keyboard) and actual exported screenshot geometry. Compare with App Store reference using crops only for measurement, clearly labeled.
- [ ] Resolve compile/test failures, report exact remaining limitations and request fresh reviewer via parent. Do not claim pixel identity from marketing images.
