# Companion implementation plan

> For agentic workers: use executing-plans task by task. Work only in companion/. No commits, deployment, real account calls or public binding.

Goal: a bounded free user-owned workspace MCP service that interoperates with the app's JSON POST subset.
Architecture: one POSIX directory-descriptor workspace, a strict authenticated session dispatcher, and a bounded localhost HTTP adapter. No external dependencies.
Tech stack: Python 3.11+ standard library, unittest, POSIX filesystem.
Spec: companion/DESIGN.md.

## Review focus
- Concurrent symlink/hardlink replacement: directory-relative nofollow operations; no host reads or modifications.
- Canceled/duplicated writes: pre-commit cancellation, no-clobber commit, used ID ledger, no automatic retry.
- Slow or malformed HTTP: absolute deadline, hard body/header limits, worker capacity and fixed errors.
- Token disclosure: secure exclusive creation/read, no response/log echo, no credentials inside served directory.
- Partial writes or fsync failure: original preserved before commit; uncertainty after commit documented.

## Task 1: filesystem and schema boundary
- [x] Author Tests requiring real Workspace(root), list_files(), read(name), write(name,text,overwrite,cancel_event) and strict decode_json/validate_arguments; run and record missing-feature RED.
- [x] Implement companion/orivyn_companion.py pure validation + Workspace with those methods, explicit close(), fixed CompanionError.
- [x] Run full companion suite for path, file bounds, atomic/cancel and schema GREEN.

## Task 2: MCP and loopback
- [x] Author authenticated real HTTP lifecycle tests with make_server(workspace,token,port=0), exact IDs/statuses, real file round trip, replay, session, malformed/body/deadline/thread limits. Run RED.
- [x] Implement Session/dispatch and local HTTP server, CLI secure token loading/generation; no public bind option.
- [x] Run whole companion suite with ResourceWarning treated as errors; record actual results, no test-only production routes.

## Task 3: delivery and review
- [x] Write companion/README.md with safe local setup, token handling, proxy prerequisites, tool examples and unsupported capabilities.
- [x] Run py_compile, companion suite and existing scripts/tests aggregate. Review the actual diff and ask integration owner to review security boundary.
- [x] Report usable local artifact and verification versus unverified remote/physical pairing; no commit or deployment.
