# Native iOS Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development to implement task-by-task.

**Goal:** Make Email, Calendar, Browser and Location useful native tools without false account connectivity.
**Architecture:** SwiftUI forms with UIKit review controllers; isolated one-shot location driver with an observable, bounded request owner. No new network backend or persistent sensitive store.
**Tech Stack:** Swift6, iOS26, MessageUI, EventKitUI, SafariServices, CoreLocation, XCTest.
**Spec:** docs/superpowers/specs/2026-11-12-native-tools-design.md

## Global constraints
- Preserve bundle/storage/Keychain identities; private source and free builds, no billing.
- Do not access inboxes, existing calendars, website data or password vaults; no automatic send/save.
- Location permission is When In Use only, initiated explicitly; no background location, geocoding or automatic sharing.
- Keep user draft/attachments intact after cancel, Back and interrupted navigation.
- Do not claim device Mail delivery, HealthKit/bank/password integration or physical GPS acceptance from simulator tests.

## Review focus
- Return from each native editor and cancellation must not overwrite another draft or create duplicate controllers.
- Invalid/oversized text or credential-bearing URLs must not leave an external side effect.
- Permission delay/cancel/background and late location callbacks must not resurrect an abandoned request.
- A native saved/queued callback is not proof of calendar synchronization or email delivery.
- Real system controllers must be used, not test-only successful substitutes.

### Task1: Real UI RED
Files: UITests/NativeToolsUITests.swift, codemagic.yaml.
- [ ] Add four real UI tests opening existing Customize routes, expecting new mail/calendar/browser/location controls, and asserting canceled flows preserve composer.
- [ ] Run isolated native workflow against absent features. Expected: missing mail.subject/calendar.title/browser.url/location.request, not build setup failure.
- [ ] Preserve exact logs/source SHA before production edits.

### Task2: Reviewed mail/calendar/browser tools (isolated worker)
Files: Core/NativeToolDrafts.swift, UI/MailDraftView.swift, UI/CalendarDraftView.swift, UI/BrowserToolView.swift, Tests/NativeToolDraftsTests.swift.
Interfaces: MailDraftView(), CalendarDraftView(), BrowserToolView(); each contains own form/state/real UIKit wrapper and navigation title. No WorkspaceViews or Info edits.
- [ ] Tests first: MailDraft.validated(recipient:subject:body:) bounds recipient320, subject512, body32768UTF8, rejectNUL and recipient newline; CalendarDraft.validated(title:notes:start:end:) bounds title480bytes/120chars,notes4096bytes,finite dates,end>start,span<=366days; BrowserDestination.validated(String) bounds4096UTF8,HTTPSonly,hostrequired,no user/password/controlchars/whitespace,port443orabsent.
- [ ] Implement pure validated values, no side effects; then native SwiftUI forms. Invalid input keeps fields and yields actionable error, never truncates.
- [ ] Mail UI IDs mail.recipient/mail.subject/mail.body/mail.review; canSendMail false leaves editable form with honest setup guidance. Review only opens MFMailComposeViewController, callback reports queued/saved/cancelled/failed accurately. No mailto fallback carrying private payload unexpectedly.
- [ ] Calendar IDs calendar.title/calendar.notes/calendar.review; defaultstart now+1hour,end+1hour; form opens actual EKEventEditViewController and does not request broad Calendar access or query calendar lists/defaults. Native Cancel/Save controls finish; canceled draft stays intact.
- [ ] Browser IDs browser.url/browser.open; present actual SFSafariViewController modally for valid URL. Never JS bridge/page extraction or automatic model input. Explain destination sees visits. Preserve address on Done; no browser object created on invalid input.
- [ ] Run native unit/UI checks, read results, report exact limitations; no commits by worker.

### Task3: Single-use location (main worker)
Files: Core/LocationSnapshot.swift, Services/OneShotLocationService.swift, UI/LocationToolView.swift, Tests/OneShotLocationTests.swift, Info.plist.
Interfaces: @MainActor LocationDriver.start(completion:) and cancel(); LocationSnapshot(latitude:longitude:accuracy:timestamp:); @MainActor @Observable OneShotLocationService with request(),cancel(clearResult:),isBusy,snapshot,error.
- [ ] Test permission/error propagation, one operation at a time, cancellation, previous callbacks after new request, invalid/nonfinite/out-of-range coordinates, negativeaccuracy, >60secondold/future>5second timestamps, timeout and clearResult.
- [ ] Implement actual CLLocationManager per driver/request on main runloop; requestWhenInUse only, requestLocation once, stopUpdatingLocation on finish/cancel. Single operation token; timeout30seconds; cancellation clears token before hardware cleanup. No actual coordinator or secret data in logs.
- [ ] UI IDs location.request/location.cancel/location.clear/location.coordinates. No prompt untilrequest; clear on disappear/background. Display timestamp/accuracy. Copy explicit only; no Maps/geocoder/network.
- [ ] Add NSLocationWhenInUseUsageDescription truthfully; no background mode, noalwayspermission.
- [ ] Test actual simulator API with declared fixed coordinates, permission onlywhenrequested, screenshot+clear. Simulator location is not physicalGPS evidence.

### Task4: Wire and full verification
Files: WorkspaceViews.swift, README/nativeQA/install docs, public catalog afterverification.
- [ ] Existing IntegrationDetailView dispatches realfourtoolviews; labels distinguish native actions from full account sync. Keep Passwords/Health/Finances honest limitations; retain existing no-account test label.
- [ ] Collect focused nativeGREEN; run full64+Python/native/UI/defaultrealinference/ARM64package suite against finalsource. Inspect screenshots,actualprivacystrings andappShortcutsmetadata.
- [ ] Stage exact artifact+catalog together and validate before activation per latest userpolicy. Do notpromote failedcandidate orbreakliveURLs.
