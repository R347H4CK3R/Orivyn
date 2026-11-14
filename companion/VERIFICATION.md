# Companion verification

Observed 2026-11-12 on Linux, Python 3.12.14. Tests use a private temporary workspace, test-only credentials and localhost sockets. No public listener, remote endpoint, personal files or external account was used.

## Test-first evidence

- Before implementation, the first 29 tests failed with explicit missing-companion-feature assertions. The test harness imported successfully and deliberately reported the absent implementation rather than mistaking a fixture/setup error for behavior.
- After implementation those 29 passed against the actual filesystem and HTTP adapter.
- Added six edge cases. A non-ASCII Authorization header exposed a real request-handler exception (connection closed instead of redacted 401). The targeted regression failed with that explicit assertion before the correction, then passed after comparing credential bytes safely.
- Added two real CLI tests for exclusive private token generation and authenticated loopback startup/clean interruption.

## Latest verified commands

- `python3 -W error::ResourceWarning -m unittest discover -s companion/tests -v`: **37 tests, 0 failures/errors**, including filesystem and HTTP round trips, malicious names, symlinks/hardlinks, count/byte/schema limits, explicit overwrite, interrupted atomic writes, pre-commit cancellation, no replay after lost response, session expiry/ID limit, worker capacity, slow-header deadline, malformed/duplicate headers, token privacy and CLI lifecycle.
- `python3 -m py_compile companion/orivyn_companion.py`: **passed**.
- `python3 -W error::ResourceWarning -m unittest discover -s scripts/tests`: **68 existing project tests passed**. This does not substitute for the separate native Swift gate.
- `git diff --check`: **clean** at local verification.

## Still unverified / deliberately unsupported

- Real Orivyn iPhone → trusted HTTPS proxy → companion pairing, real-account provider acceptance and macOS deployment are not verified by loopback tests.
- OS sandbox resistance against the same user/root, arbitrary concurrent host writers, full virtual desktop, browser control, shell commands, app access and remote LLMs are not provided.
- A canceled/disconnected write can already have committed. A fixed error or lost response does not prove rollback. Inspect the workspace before retrying, and do not replay automatically.
- Independent source review is requested before integration/publication. No source commit or deployment was performed by this worker.
