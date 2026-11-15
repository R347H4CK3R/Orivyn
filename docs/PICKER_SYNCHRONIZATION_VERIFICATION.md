# Picker synchronization verification

Source 094b1979ce14452747d4854a11597fe252b0ffb2 passed three independent native repetitions in run43673325415/job132687948443. Downloaded artifact14146231806 verifies exactly one passed test per attempt, zero failures and zero skips. Durations:85.531s,57.319s,43.494s.

The prior generic Cancel selector exposed PUPickerUnavailableView while Photos loaded, then a different Photos navigation control. The tested helper waits for the actual Photos navigation bar, resolves its Cancel, validates visible unchanged geometry, performs one tap, and requires dismissal. All three captured Cancel frames were (24,127,36,36), hittable=true. Files cancellation still requires stable/hittable geometry; the test retains draft preservation and send-enabled assertions. No production picker behavior changed.

The exact tested UITests/JarvisEVOAttachmentUITests.swift is retained on codex/boundary-repeat-20261115 at094b197. It is ready to combine with the next validated implementation integration. No extra full native run is started just for this test-only change. This does not establish a root-cause fix for every earlier blank Files or intermittent navigation failure, nor physical-device behavior.
