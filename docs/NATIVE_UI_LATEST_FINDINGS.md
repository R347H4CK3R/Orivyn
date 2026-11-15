# Latest native UI findings

Source fb146910cfca0bd466b9b28b8feaf4202ae1de74 completed native core tests (1,014, five skipped, zero failures), UI shard 0 passed, and UI shards 1 and 2 failed in https://github.com/R347H4CK3R/Orivyn/actions/runs/43658683246 .

Shard 1: 16 of 17 tests passed. AutomaticRealInferenceUITests generated a real Paris answer, then the New conversation tap did not clear the old response within ten seconds. Captured accessibility trees before/after retain that response and show no error alert. The current cause is unresolved: no production navigation or persistence behavior has been changed on this evidence. The earlier composer text test passed in this run.

Shard 2: ten of eleven tests passed. LocalAgentIntegrationUITests tried to tap agent.create immediately after typing the goal. The control still exists in LocalAgentView, below added plan guidance in a lazy Form. The test now uses the existing bounded reveal helper before Create and the newly inserted Run control, preserving exact draft, durable relaunch and no-automatic-execution assertions. The change requires a native rerun; parsing alone does not prove the UI regression fixed.

General-agent native inference separately failed the requested search/read answer. Four other production inference gates passed. Build 8 packaging succeeded from a6c696a, but that package remains unpublished and is not full app acceptance.
