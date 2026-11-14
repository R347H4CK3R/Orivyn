# Codex Work portable development checkpoint — 2026-11-14

Baseline: private draft PR #4, `integration/native-candidate-20261113-220952-209d7ae4`, verified at `3d5437750dfe1d575434821840e355a6acc1d472`. All 590 tracked blob identities matched the isolated local checkout before editing. The repository remains private; this checkpoint is not an IPA, release, merge, or 1.0.0 completion claim.

## Implemented

- Remote text streaming now accepts only a sole choice with index zero (or an omitted index for older compatible servers). Unexpected indices, malformed indices and multiple choices cannot contribute text or a completion marker to the displayed answer. Existing usage frames, indexless responses, stop/EOF checks and unsupported-tool rejection remain covered.
- Added `scripts/run_portable_checks.py`: one local command for Python contracts, catalog validation, JavaScript agent/VM checks and exact production Foundation Swift tests. It retains logs, a source SHA-256 manifest and a JSON summary, continues independent stages after failure, rejects existing evidence directories and fails on missing executables. SQLite amalgamation tests are opt-in and explicitly skipped otherwise. VM BIOS output goes into the evidence directory when invoked by this runner.
- README now reflects the owner's instruction to skip Mac runners during ongoing development.

## Observed verification

- Regression before the decoder fix: the new indexed-choice cases produced 13 failing assertions across three tests. The valid index-zero case already passed. The old decoder accepted other-choice text and stop, mixed-choice envelopes and malformed index types.
- After the fix: **396 Foundation Swift XCTest cases passed**, zero failures, using installed Swift 6.1.3 on Linux. This harness excludes the known unsupported Linux custom-URLProtocol redirect fixture; that Apple test has not passed here.
- **159 Python tests ran: 158 passed, one existing real-tokenizer test skipped.** Catalog generation check passed.
- **98 JavaScript agent tests and 39 VM component tests passed.** Actual bundled BIOS execution in the Linux host is component evidence, not WKWebView or iPhone verification.
- A separate exact-production persistence harness passed **40 tests**, using the existing local SQLite header and host shared library. Its source/header/library identities and command were recorded. The aggregate runner's optional SQLite-amalgamation stage was skipped because no amalgamation was supplied; the separate host-library run does not change that recorded skip.
- Whitespace/diff checks passed. No remote provider or account was contacted by these tests.

Test counts describe individual suites and overlap; they are not a count of distinct application acceptance requirements.

## Remaining work and limits

Apple SDK compilation/linking, simulator/UI checks, physical iPhone install, file protection, microphone/audio routing, thermal/memory/HDMI behavior and actual service acceptance remain unrun for this source. No Mac runner was requested or started. No paid service, version bump, catalog activation or publication occurred.

The separate borrowed-model native read-gate candidate remains dormant. Its supplied README reports a sole admitted 2,497,280,256-byte Qwen3 model versus the app's 2,000,000,000-byte model cap, absent combined Apple runtime packaging, and unfinished generation driver, lease/unload cancellation barriers and durable reviewed-plan integration. This checkpoint does not relax that cap, copy the bridge into production, or claim its isolated tests prove app integration.

The release ledger's broader gaps remain: dependable general autonomous tool use, visual image understanding, automatic cross-device synchronization and self-applied repository repair. Skipping Mac verification does not implement those capabilities. Continue these as explicit engineering work, retaining current data/storage identities and existing functionality; do not mark the application complete based on this checkpoint.


## Next implemented slice: source patch export

Source-repair previews can now be exported explicitly as portable patches carrying the pinned source identity and not-applied/not-tested status. Export eligibility uses exact reviewed UTF-8 bytes. Six new real-Git export regressions and four Swift binding cases pass; the full portable result is now 400 Foundation, 104 agent and 39 VM tests, plus 159 Python tests with one skip. See `READ_ROUTING_AND_REPAIR_PREVIEW.md` for detailed evidence and limitations. Native export behavior remains unverified.

The owner later set a two-hour publishing target and explicitly authorized **a free Mac runner for packaging**, superseding the prior no-Mac constraint for that purpose. Live CircleCI capacity was checked: 1,159 of 30,000 free credits remain, insufficient for a confidently budgeted full native gate. No paid plan or underfunded run was started. An Appcircle sign-in/account choice is pending. Publishing is authorized, but still requires a newly built and inspected IPA; do not substitute an old binary or label unfinished 1.0.0 capabilities complete.
