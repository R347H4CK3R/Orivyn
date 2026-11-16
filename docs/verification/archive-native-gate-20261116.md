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
