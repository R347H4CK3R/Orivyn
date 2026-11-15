# Integrated cancellation verification

Source 436e9448635303cf46433021cd82f2453612b735 passed all 24 native checks in run 43669524078: 8 authentication, 7 channel, 9 text exchanges. Downloaded artifact 14143852441 provides exact source hashes and includes the successful cancel-sender-after-request case. This verifies the integrated native host component, not shipping iOS sync.

Portable verification on the same source passed in run 43669523994. Its native app core job 132676236657 did not execute tests: simulator boot twice timed out waiting for BackBoard, with one successful targeted shutdown between attempts. GitHub rejected a single-job retry because other jobs in run 43669523997 were still running. Preserve that first failure and retry only the core job once the run completes; do not change pass criteria or classify it as an app test pass.

General native agent inference still failed at ProductionLocalAgentSessionTests.swift:130 and :133: it did not read the required message or copy its unpredictable marker. UI shard 1 passed. Other UI jobs and isolated boundary diagnostics remain in progress at this record.

Build 8 is a separately published, older prerelease. None of these later checks is exact-package acceptance for it.
