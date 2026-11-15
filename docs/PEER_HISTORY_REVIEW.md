# Receive ownership review

Independent review of a3f7da4 found no established Critical issue, but an Important retry gap: preflight clears attachmentHistoryIsLoaded; stale/read/cancel failures release the lock without a receive recovery route. Both later receive admission and post-commit recovery reject. An unrelated bootstrap can reload but is not a safe implicit answer for unsaved history.

Before correcting the candidate, the stale rejection test now requires a later safe retry after the database again matches the retained app state. Added real post-commit task cancellation and real attachment-file retention checks. Seven native tests are requested. This revision intentionally preserves the reported defect to prove the regression. Do not integrate.

Other requested coverage remains: unsaved in-memory history, failed/competing recovery and exclusion while reconciliation is suspended. Guarded transport-wrapper compilation and real lifecycle integration remain separate pending gates.
