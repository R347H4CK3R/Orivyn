# Verified development progress

Build 8 is published as an incomplete prerelease; see BUILD8_PUBLICATION.md. Subsequent changes below are not in that IPA.

- Peer app dependencies/notices integrated at 86c3717 after actual iPhone and simulator app compile gate 43672467858 passed. See PEER_APP_INTEGRATION_STATUS.md. Normal shipping builds still disable the peer SPI.
- Full native run 43669523997 at 436e944 passed all three UI groups. Core failed simulator boot before tests; only that job was retried once after the workflow finished. Inference genuinely failed premature-answer checks; it was not retried unchanged.
- Picker stabilization experiment 782c41d failed three of three repetitions before Cancel. Native AX showed a temporary PUPickerUnavailableView Cancel followed by Photos Cancel. Isolated follow-up 094b197 tests resolving the Photos navigation control and one geometry-validated tap; pending, not a production repair.
- Native tool transcript experiment aedc156, run 43672816771, verified artifacts show 4/4 required reads versus 0/4 flat baseline on the same Q4 model and 4096 context. Includes two holdouts. No tools executed or complete workflow tested. Follow-up 38dcefe tests the production 2048 context budget. No production protocol change yet.
- Vision remains 8/10 on the frozen checks. Q8 precision did not improve the two failures; no model switch integrated.

General autonomy, reliable broad vision, peer pairing and live automatic sync, and physical-device acceptance remain unfinished. Passing diagnostic observations or compilation is not full acceptance. Do not assign a fabricated overall completion percentage.
