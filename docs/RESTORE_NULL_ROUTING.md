# Restore optional routing compatibility

Follow-up to build 16, not a published update. Synthetic conversation JSON with
assistant `channel: null` or `recipient: null` was silently omitted, although the
same message with absent fields was accepted. Foundation JSON decoding represents
explicit null as NSNull; the converter previously checked only missing values.

The converter now treats null as absent for these two optional routing fields.
Non-null routing must still be exactly `final` / `all`. Internal channels, tool
recipients, malformed types, hidden/user-system messages and do-not-remember
metadata remain excluded. This does not infer attachment mappings or change
original-archive preservation, database identities, or existing imported data.

Three added tests cover all nine absent/null/explicit combinations, seven negative
routing cases, and three privacy flags with null routing. Before the fix the first
regression produced nine assertion failures across three null combinations; the
negative-routing test passed. Native archive gate expects 212 tests instead of 209
because its selected converter suite now contains three additional tests. That is
a future requirement, not a native pass claim.

No private archive was inspected or uploaded. Physical-device behavior, full
private-backup/media restoration, and native verification of this follow-up remain
unverified. Build 16 and its public catalog entries are unchanged.

Local verification: final snapshot passed 610 Foundation tests on Swift 6.0.3/Linux.
The portable aggregate passed guest materialization, catalog validation, Python
(280 tests, one existing optional-dependency skip), agent and VM tests. After the
native expected-count edit, all 280 Python tests were rerun with the same one skip;
`bash -n` and `git diff --check` passed. Linux URLProtocol redirect remains excluded
by the existing harness. SQLite was not run (no amalgamation supplied). Final
Foundation evidence: `/tmp/orivyn-null-final`; broader stage evidence:
`/tmp/orivyn-null-green`. Independent code review found no blocker.
