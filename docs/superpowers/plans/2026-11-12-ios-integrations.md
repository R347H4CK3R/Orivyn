# Orivyn iOS Integrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver real free cross-app text staging and local reminders, with exact-source native evidence.
**Architecture:** Native SwiftUI/App Intents, a bounded in-process incoming-text inbox and review UI, and an injected UserNotifications boundary whose actual pending requests remain authoritative.
**Tech Stack:** Swift 6, iOS 26, XCTest, XcodeGen, existing llama.cpp runtime.
**Spec:** `docs/superpowers/specs/2026-11-12-ios-integrations-design.md`

## Global Constraints
- No paid tiers, billing, backend accounts or automatic external actions.
- Preserve app.jarvisevo.ios, module/scheme/storage/Keychain identities and historical branches.
- URL 32,768 UTF-8 bytes; incoming text 8,192 bytes; combined draft 32,768 bytes.
- 48 app-owned reminders; title 1–120 characters, notes at most 2,000 UTF-8 bytes; date at least 5 seconds ahead and at most 365 days ahead.
- Explicit review and notification approval; never silently overwrite a draft/request or simulate execution.

## Review Focus
- Repeated/new incoming links during review must preserve the first pending payload and current composer.
- Cancellation, scene changes and active voice/import/generation must not submit or overwrite text.
- Permission denial, failed OS scheduling and capacity exhaustion must leave no optimistic successful reminder.
- Unrelated/malformed OS notifications must not be shown or removed as Orivyn reminders.
- Relaunch must reconcile the actual OS queue and not recreate canceled/expired notifications.

### Task 1: Red UI acceptance
**Files:** `UITests/OrivynIntegrationUITests.swift`; isolated manual Codemagic workflow.
- [ ] Add real URL-review/cancel/append and reminder-create/relaunch/cancel UI tests against current app.
- [ ] Run focused native UI checks and retain expected feature-missing failures before implementation.

### Task 2: Reviewed cross-app text
**Files:** `Core/IncomingText.swift`, `Services/OrivynIntents.swift`, `UI/IncomingTextView.swift`, `UI/AppModel.swift`, `UI/JarvisEVOApp.swift`, `UI/RootView.swift`, `Info.plist`, `Tests/IncomingTextTests.swift`.
**Interfaces:** `IncomingTextRequest.parse(URL) throws`, `IncomingTextInbox.enqueue(String) throws`, `AppModel.acceptIncomingText(String) throws`.
- [ ] Add native parser/inbox/draft/intent tests with literal malformed and boundary inputs.
- [ ] Implement bounded staging and explicit append/cancel review; wire URL scheme and App Shortcuts.
- [ ] Preserve audio/import ownership, current draft and attachments; run focused tests then full suite.

### Task 3: Actual local reminders
**Files:** `Core/LocalReminder.swift`, `Services/ReminderScheduler.swift`, `UI/ScheduledRemindersView.swift`, `UI/WorkspaceViews.swift`, `Tests/ReminderSchedulerTests.swift`.
**Interfaces:** `LocalReminder.validated(title:notes:date:now:) throws`; `ReminderNotifications` async permission/pending/add/remove boundary; `ReminderScheduler.refresh/create/cancel`.
- [ ] Test validation, denied permission, concurrency, existing queue limit, add failure, payload round-trip and unrelated-request isolation.
- [ ] Implement UserNotifications adapter, authoritative scheduler and create/list/cancel UI with privacy/availability copy.
- [ ] Verify real simulator scheduling, relaunch and cancel; preserve canceled form/draft behavior.

### Task 4: Full verification and private delivery
**Files:** live feedback URL, build metadata, current feature/install docs, QA report.
- [ ] Confirm renamed private repository URL before updating live feedback links.
- [ ] Review changes; run full Python/native/UI suite, actual default inference and ARM64 packaging.
- [ ] Verify all catalog full-file integrity/CPU probes; keep device/quality limits explicit.
- [ ] Independently verify exact IPA and screenshots, preserve source and evidence in Library, prepare private prerelease only with verified scope/access. Report signing/hardware blockers.
