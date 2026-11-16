# Chat-local task native interaction regressions

Baseline: b7c67fa. Three native UI tests are authored, not executed in this Linux workspace:

- `ChatLocalTaskUITests.testSavedAnswerInspectionPreservesChatDraftAndEvidence`: opens actual chat task card and existing task panel, checks explicitly synthetic answer/evidence, returns to unchanged composer.
- `ChatLocalTaskUITests.testResumeWithoutLocalModelRejectsAndPreservesInterruptedState`: opens an interrupted record, checks no automatic execution, explicitly taps Resume and requires missing-local-model rejection with unchanged interrupted state. This is NOT successful resume or inference verification.
- `ChatLocalTaskUITests.testDifferentChatCannotInspectOrResumeOriginTaskThroughManualPanel`: requires bounded disappearance of origin-chat cards after selecting another chat, then actual manual task selection must reject cross-origin access without presenting Run or an answer.

## Fixture scope
The existing DEBUG-only RootViewRegressionFixtureHost gains `chat-local-tasks`, reachable only with both explicit test flags. It creates a unique temporary store, synthetic conversations and two labeled task records through the production reducer and atomic LocalAgentStore. No local model is installed, no inference/tool runner is invoked, no private data is used. The normal Release path excludes this entire fixture file. Production changes are accessibility identifiers only.

## Local checks
- Swift frontend syntax parsing with DEBUG enabled and disabled passes; not Apple typechecking.
- Actual production JavaScript reducer validates both fixture transitions and idempotent recovery. Initial plain-string evidence was rejected by the reducer; corrected to the strict get_app_info result schema, preserving synthetic labels. UI assertions do not claim that fixture evidence came from a real tool call.
- git diff --check passes.
- Repository Python suite: 271 tests, existing 4 failures, 4 errors, 1 skip. Failures remain attachment fitting tokenizer source contract, explicit-model gate all-success, import disclosure source contract, Files cancellation source contract; errors remain three explicit-model pipeline fixtures and absent generated VM image. These were reproduced on the prior unchanged development baseline; no unrelated repairs attempted.

No CI dispatch, IPA packaging, publication or device verification. Actual simulator accessibility and layout behavior remain pending native execution. Successful real-model free-form planning and resumed execution are separate acceptance requirements, not satisfied by this fixture.

Combined integration with reviewed Python harness refresh and natural local
read aliases passed 566 exact-source portable XCTest cases and 271 Python tests
with zero failures/errors and the existing one real-tokenizer skip. The Linux
redirect fixture exclusion remains; neither result verifies these three native
UI tests. The existing queued native run predates this integration and is not
evidence for these new selectors. No release or additional CI was dispatched.
