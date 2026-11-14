# Active-session recovery guard (candidate, not native verified)

Opening a second local-agent or verified-read view previously called the recovery loop while another shared session owned work. The loop could mark a live running record interrupted and persist a newer revision, causing the owning session's later result write to fail revision validation.

Both reload entry points now return while their shared owner or local task is active. Idle/relaunch recovery is unchanged. Two native tests cover opening/reloading a second session while a lease exists, byte-identical retention of running records, and recovery after the lease is released.

Verification: new structural regression failed before the guards; all 143 Python tests and all 83 portable agent JavaScript tests passed afterward. `git diff --check` passed. The two native XCTest regressions were authored but could not run: this executor has no Swift compiler/Xcode. This is not evidence of complete native agent reliability or release readiness.
