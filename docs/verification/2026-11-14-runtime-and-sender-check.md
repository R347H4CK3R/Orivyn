# Independent Apple/runtime and revision-sender checkpoint — 2026-11-14 23:46 UTC

Latest complete-capabilities source inspected/tested:277ec3af7e8ae5df8d54231b2f3a559bfdddce5c. Separate peer-authentication test branch42ebe15 has queued workflow43654707674; it is not a completed native authentication result.

## Verified Apple repair and inference boundaries
Fetched actual inference job132614347823 for run43649423272 at dfa998a. Combined runtime platform/header/symbol checks passed, verifying the lipo argument-order correction beyond the earlier shell double.
Actual outcome lines: vision=0, native_tools_q8=0, native_tools_q4=0, local_agent_q4=1, reviewed_plan_q4=0.
Production vision test passed71.476s; Q8 native suggestion/reload passed63.353s; Q4 native suggestion/reload passed51.174s; reviewed model proposal/approval/read test passed63.054s. These are simulator test durations, not phone latency or single-token benchmarks.
ProductionLocalAgentSessionTests still failed: answer did not copy the stored unpredictable marker and required read provenance was absent. The overall inference job correctly failed. No failed result was discarded.
https://github.com/R347H4CK3R/Orivyn/actions/runs/43649423272

## Durable revision sender
Actual portable job132628219299, run43653937608, source277ec3a:129 production Swift/SQLite tests passed, zero failures. Includes revision sender durability, concurrent stores, exact-receipt matching, late-receipt handling and erasure behavior. Tests simulate two databases, not two networked devices.
Reviewed sender documentation explicitly keeps these APIs dormant. No automatic sender/listener or background sync service is enabled. Authenticated transport, lifecycle leases, review/send integration and two-device acceptance remain outstanding.
https://github.com/R347H4CK3R/Orivyn/actions/runs/43653937608

## Fresh local checks at277ec3a
208 Python tests executed:207 passed, one real-tokenizer skip.
134 JavaScript agent tests passed, zero failures/skips.
Model catalog check passed. Clean worktree; no product mutation made during this independent check.

## Reliability and release boundary
Latest repository reliability record preserves a quoted-title host workflow pass while three unquoted-title cases still fail. Vision QualityV1 diagnostic records8/10; ineffective7/10 prompt experiment was rejected, not promoted. These records do not establish general autonomy/broad vision.
Public release listing remains0.1.1 build6 published2026-11-14 17:19:48 UTC. No new IPA publication here; build7 remains a prior independently package-verified candidate.
No physical iPhone/voice/HDMI/SideStore or visual-parity acceptance evidence added. Next objective: resolve autonomous read completion and validate native peer authentication, while keeping exact-source native acceptance separate from host/component tests. Periodic validation is not continuous execution.
