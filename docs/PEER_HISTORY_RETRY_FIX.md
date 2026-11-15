# Receive preflight retry correction

Run43675182727 at75727fb executed seven tests: six passed; the new retry after stale-state rejection failed with busy at line130. Actual post-commit cancellation and real attachment retention passed.

Admission now always verifies a fresh persisted/in-memory comparison under the history lock, rather than rejecting on the old cleanup-validity flag. Cleanup is invalidated before that read, restored only after exact equality, then invalidated again immediately before transfer. A stale/read failure preserves in-memory contents and attachment files, and permits another validating preflight. Cancellation after a validated preflight can release safely. Failed post-transfer reload still retains the mutation lock and explicit recovery path. Independent review accepted this ordering, assuming conversation writes use AppModel ownership.

The unchanged retry assertion is rerun. An eighth test creates a genuinely unsaved local turn using a real SQLite save failure and a newer composer draft; receive must reject without discarding either. Failed recovery now explicitly must retain exclusion. Syntax checks passed; native execution pending. Suspended reconciliation and competing recoveries remain unverified. No app listener, pairing flow or automatic scheduler is enabled, and no publication occurs.
