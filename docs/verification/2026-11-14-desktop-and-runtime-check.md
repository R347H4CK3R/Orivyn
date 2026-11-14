# Independent validation — November 14, 2026 22:47 UTC

Current source: dfa998a7604007c331428bafb0e1ba709d346e62 on codex/complete-capabilities-20261114, inspected in clean detached worktree.
Public release listing still shows0.1.1 build6 (2026-11-14 17:19:48 UTC). No new publication or signing performed.

## Fresh portable results
208 Python tests executed:207 passed, one existing real-tokenizer skip.
134 JavaScript agent tests passed, zero failures/skips. Model catalog check passed.
These independently rerun suites do not replace native semantic/device acceptance.

## Native progress
Run43647245211 at dd7f540: native core and all three UI jobs succeeded; inference job failed. Retrieved actual UI-0 job132607672196:23 tests, zero failures, including two virtual-desktop tests. This establishes a simulator regression pass for the formerly failing desktop flows, not physical HDMI/keyboard acceptance.
Run: https://github.com/R347H4CK3R/Orivyn/actions/runs/43647245211
Actual inference job132607671984: vision passed; native-tools failed with expiration status3 at62.431s and73.682s. ProductionLocalAgentSessionTests failed to copy the stored unpredictable marker and lacked the expected read result; ProductionReviewedReadPlanTests rejected an incorrect requested read scope. Prior isolated passing native-tools runs do not erase these newer failures.
Frozen independent host evaluation report records2/9 contract completions (the two search-only goals), with seven read-mode failures safely rejected before approval. Safe refusal is not task completion; no general autonomy claim.

## Runtime-build diagnosis and independently checked correction
Actual job132608354074 at03552cb failed before inference: Apple lipo treated the framework path after -verify_arch as an architecture flag.
Current dfa998a moves the input before -verify_arch in both generated build script and source recipe. Existing generator regression checks preserve that correction.
Independently ran the exact shell test recipe with the old argument order:exit19. Restored the current order in memory:exit0. This uses the repository xcrun test double, not a local Apple binary. Full Python suite passes. Native rebuild success for dfa998a remains pending; no production settings or acceptance limits were weakened.
Workflow43649423272 was queued during this check. No jobs were dispatched/cancelled by this session.

## Next work and limitations
Validate the corrected runtime build, then run actual Q4/native and grounded-read acceptance. Investigate wrong proposals/answers without replacing the model decision with canned results or weakening provenance checks.
Build7 remains a previously independently package-verified CI candidate. Voice/audio, SideStore/real-device install, HDMI, visual parity and full1.0.0 acceptance remain unverified. Latest code also adds secure peer revocation groundwork, not complete cross-device sync. This report covers one bounded work session, not continuous background execution.
