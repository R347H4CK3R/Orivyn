# First native archive gate: failed, retained evidence

Source `6d583b5505ae8b1b346678c0d701c13b15b8464f`.
Run https://github.com/R347H4CK3R/Orivyn/actions/runs/43810971432
Artifact `14202086246` contains synthetic-only test logs, results and recordings.

The combined native runtime build succeeded and the iOS app/tests compiled.
The native/simulator suite executed 51 tests: **43 passed, 8 failed, 0 skipped**.

- Preservation: 9 passed.
- SQLite archive persistence: 9 passed.
- Conversation conversion: 14 passed.
- Record stream: 5 passed.
- Attachment association: 5 passed, 6 failed with invalidPath on valid fixtures.
- UI: picker cancel/reopen passed; two real ZIP selection flows timed out waiting
  for the Files picker to dismiss. Neither established reviewed restore completion.

These failures remain meaningful. Investigate canonical URL path equality on
Darwin and the actual Files cell selection target using retained recordings.
Do not replace this evidence with an unqualified success claim or skip assertions.

The next single integrated gate adds the conversation answer-boundary and scoped
local-tool changes: 15 component tests and 5 actual AppModel persistence/routing
tests, plus two root-path regression tests, for 73 mandatory native/simulator tests. Passing Linux components does not
establish model answer quality, UI interaction, attachment mapping, general
agentic capability or physical-device acceptance. The user's private archive is
never supplied to CI. No IPA or completed 1.0 release was produced by this gate.

Mac-hosted ArchiveExtraction package tests also passed 17/17. The candidate fixes
URL directory-hint equality without accepting symlink/noncanonical roots, and
selects the Files ZIP cell instead of its text label. Native rerun is required.

Final integrated gate also includes one deterministic capability-inventory test
and one pinned actual-model semantic test (three synthetic prompts), raising the
required native/simulator count to 75. The integrated portable suite passes 531
tests with the previously documented Linux URLProtocol redirect exclusion.
An attempted rerun with a mistyped exclusion hit that unsupported Foundation
callback; the corrected run passed. No native semantic pass is inferred.

## Combined rerun 43816635355

Source `7ea326d6c17a9f82b3fc4a9c66a7f97826973844`, iPhone 16 Plus
simulator iOS 26.1. Result: **73 of 75 native/simulator tests passed,
2 failed, 0 skipped**. Separate macOS ZIP extractor: 17 passed, 0 failed.
Artifact `14203604106`, SHA-256
`49c56f37ab1632df12def53de8a79ea9eea6cd268faca701625ee8236b8a30f1`.
This is a failed acceptance gate, not release approval.

Verified: all 13 attachment association path tests; synthetic ZIP picked through
Files, reviewed, transactionally committed, and history visible after relaunch;
retained prepared ZIP survives relaunch without activating before confirmation.
The five selected AppModel conversation/local-tool integration tests passed.

Remaining failures:
- `ProductionConversationResponseTests/testPinnedModelWritesPythonAndDescribesActualLimitsWithoutEcho`:
  Python and direct Paris checks passed; capability answer failed app-information,
  memory-search and supported-autonomy assertions. Generated capability prose is
  not reliable solely because policy text is present. Preserve the assertions.
- `ArchiveRestoreUITests/testRealZIPPickerCancelsAndReopensWithoutRestore` line 92:
  first picker presentation was not observed after Choose ZIP. Failure preceded
  cancellation/reopening; other two real-picker paths passed. Investigate actual
  presentation lifecycle/test interaction; do not replace the picker with mocks.

Private archive, physical-device behavior, actual media association and broader
autonomous plugin orchestration remain unverified. New plugin-result handoff and
proposal-filter candidate were not part of this run.
