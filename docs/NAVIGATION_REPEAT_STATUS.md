# Targeted navigation verification — 2026-11-15

Source: d388dd4ec39d09ee640bb60fd07f2a2cac3a9187 (isolated diagnostic branch).
Run: https://github.com/R347H4CK3R/Orivyn/actions/runs/43666521398
Artifact: 14142719553.

Three independent executions of AutomaticRealInferenceUITests/testActualGeneralCoderDownloadSwitchAndRelaunch passed, each with one executed test, zero failures and zero skips on the iOS 26.0.1 ARM64 simulator. Durations: 220.987, 143.809 and 170.319 seconds.

Debug lifecycle logging recorded two successful new-conversation transitions per attempt: tap, admission, database save completion, selected conversation with zero messages, and changed selection. The exports are cumulative one-hour logs: counts 2/4/6 represent six total transitions, not twelve independent observations.

This does not reproduce or repair the earlier intermittent failure. No production navigation behavior was changed. The isolated Xcode version-capture build correction completed successfully before these tests; that pipeline repair is separate from application navigation.

Other native UI failures remain: Photos cancellation followed by a blank Files picker, and checkpoint restoration after app relaunch. Their causes have not been demonstrated. No physical-device or release acceptance is established.
