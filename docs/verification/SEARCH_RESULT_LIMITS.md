# Saved-memory result-limit disclosure repair

The production local memory tool previously returned at most the requested number of matching notes without saying that further matching notes had been omitted. `searchLimited` only described the 500-note scan boundary, not the result limit.

The tool now returns `totalMatchesInWindow` and `resultsLimited`, separately from the scan-bound flag. The local model prompt asks for partial-result disclosure. The deterministic verified-read reducer strictly validates the new count/flag pair while accepting old saved results unchanged. It does not rewrite historical evidence.

Verification on Linux: exact production Swift search_memory branch compiled and executed. A regression failed before the repair (missing match total) and passes afterwards. Its real payload is accepted, reported and recovered by both production JS reducers. All 82 JS tests and 142 Python tests passed. A prompt-budget regression initially caught an overlong instruction; the instruction was shortened and the existing bound remains unchanged.

These tests do not prove model obedience, iOS UI behavior, native compilation, device installation or release readiness. Follow-up: conversation search now provides the same bounded total and result-limit disclosure. Its exact production Swift branch passed empty, full, capped and out-of-window checks, and its actual result passed both production JS report/recovery paths. All 83 JS and 142 Python tests passed after this follow-up. Saved legacy conversation results remain unchanged and accepted. Source and small evidence are preserved together.
