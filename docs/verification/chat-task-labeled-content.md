# Native saved-task labeled content assertion correction

Artifact 14211224833 reports 191/194 passing, zero skipped. Both plugin
presentation tests and cross-chat ownership UI test passed. Saved answered-task
inspection and no-model resume UI reached the real task sheet, then failed
exact state-label equality: iOS 26.1 reports `State, answered` and
`State, interrupted`, not the bare values. LocalAgentView uses SwiftUI
LabeledContent, which combines its label and value for accessibility.

The native tests now assert those exact combined labels both before and after
rejected resume. The analogous steps LabeledContent assertion expects
`Read-only tool steps, 1/6`; this row had not yet been reached in the failing
run, so its native assertion still needs execution. No contains/substring or
allowed-state relaxation is introduced. State values, step count, answer,
recorded evidence, draft preservation, and zero-replay expectations remain.
No production UI or model code changes. Add retained opened-sheet hierarchy and
screenshot before assertions to expose any further native mismatch directly.

Swift syntax and git diff checks pass. Native rerun remains required. These two
tests have not yet passed their complete paths; the two plugin presentation and
cross-chat tests did pass in the retained run. No CI dispatched here.
