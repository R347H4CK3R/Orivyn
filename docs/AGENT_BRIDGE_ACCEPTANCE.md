# Executed Swift-to-JS agent boundary checks

The reproducible `scripts/run_agent_bridge_smoke.py` compiles exact production Swift storage, JSON/schema, error, and result-budget sources and executes the production JS reducer under Node. Test-only drivers orchestrate subprocesses and fixtures; no production code changed in this pass.

Proof 45 passes 76 explicit checks: persist and reopen a running task, require interrupted status before explicit resume, preserve interrupted history, fit a control/Unicode-heavy result to 3747 bytes (nine retained rows, one explicitly omitted), reject stale completion and revision rollback, read the earlier result after a newer tool result, reconstruct all UTF-8 pages byte-for-byte, archive/restore without mutation, and preserve answered state on reopen. Retained row content is verified, subprocesses have timeouts and paging is bounded.

An isolated copy with result budgeting bypassed fails the byte-limit assertion as expected. The production sources were not mutated. Initial harness compilation missed MCPToolSchema; proof42 records that harness-only failure. Proof45 is the final passing run.

134 Python unittest checks and 70 agent Node tests pass. An attempted pytest invocation failed because pytest is not installed; the actual project unittest suite was then run successfully. Earlier 250 Swift XCTest and 24 static Observation checks are unchanged, not rerun here.

This is NOT an iPhone end-to-end test: native LocalAgentSession, LocalReadTools/AppModel dispatch, JavaScriptCore, UI, model-generated decisions, physical restarts and file protection are not exercised. Tool fixtures are synthetic; answer text is deliberately supplied by the test, not an AI. Full native compilation and actual model task success remain required before release. No paid build, IPA, catalog, or public release changed.
