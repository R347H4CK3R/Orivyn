# Uniform-border diagnostic rejected for general use

The foreground-centered crop on this isolated branch was rejected on code review because it can move off-center objects to the image center and change absolute-position semantics. It must not be merged as a general image-analysis preprocessor.

Run 43679547008 failed before inference because shallow checkout did not contain the baseline commit. Run 43679738991 then built both libraries and verified the pinned production model pair, but inherited shell errexit ended evaluation after baseline quality failure. Only the unchanged baseline's ten frozen cases executed: 8/10, case02 incorrectly left, case08 incorrectly five. All ten returned native status0 with zero tracked handles. No candidate result or independent holdout pass is claimed. Exact raw output and provenance are retained in docs/evidence/vision-border-baseline-20261115.json (artifact14148031841).

A separate center-preserving candidate expands holdouts to original-image absolute positions and two pinned natural photographs. Neither branch changes the model catalog, user data, published preview, or release status. These diagnostics use local Linux CPU model inference, not iOS/device acceptance.
