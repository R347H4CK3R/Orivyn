# Production-context autonomy verification

Run 43673378514 at 38dcefef6d44c720793fe9fffc6bc8cf5e159743 completed successfully. Independently downloaded artifact 14145068991 confirms native tool transcripts selected the required read in 4/4 cases, including two held-out conversation names/IDs/message indices. Flat baseline selected 0/4 and answered prematurely. Both arms used the pinned Q4 model, 2048 context and 384 output tokens. This repeats the improvement observed at 4096 context.

This verifies next-decision selection only: tools were not executed, no final grounded answer was tested, and the diagnostic CLI is not the production iOS bridge. No production protocol is changed. Complete SQLite-fixture workflows with fresh unpredictable answer markers and two new holdouts are committed separately at 99f615720968fbc85c0a58efffe7678dd0f7dc7f. Their result is pending.

Picker follow-up 094b1979ce14452747d4854a11597fe252b0ffb2 remains queued in run 43673325415. It is not called fixed.

Sync receive ownership regressions are isolated at 05dc47e8d9ee7202bd6d2cf32943956ed4c40ba8. Five actual AppModel/SQLite tests cover committed reload and composer retention, lost acknowledgement, exclusive history ownership, stale-history rejection and failed-reload recovery. This is a deliberate red-stage commit with receive admission unavailable, not a completed feature. It is not integrated or published. The app's transport authentication and peer consent requirements remain mandatory.
