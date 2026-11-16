# Normal-chat bounded arithmetic

The normal local-model loop can now propose `calculate` in addition to its three
existing local reads. Legacy direct-read/checklist contracts and JavaScript
reducer authority are unchanged. No new remote tool, code evaluator, installation,
file access, or persistent replay authority is added.

`NormalChatToolAction` wraps existing read actions or a calculator expression.
Before writing a started receipt or dispatching a calculation, the expression is
validated against the full fresh user request by `LocalCalculatorRequest`.
Only explicit arithmetic, optionally prefixed with `please calculate`, is accepted.
Number spelling, signs and parentheses cannot change; whitespace/operator glyph
normalization follows the existing parser. Word problems and appended instructions
are not translated or stripped. AppModel also supplies the immutable original
goal to the native dispatcher. The existing parser permits only bounded arithmetic:
256 input bytes, 32 nested levels, 128 operations, finite approximate Double
results. This is not exact decimal or financial arithmetic.

Before a success receipt or further inference, `LocalCalculationEvidence`
recomputes the expected result and checks the entire result object. Forged or
mismatched output stops the loop. Existing acknowledged receipt persistence,
conversation/provider revision checks, cancellation, three-call/four-decision,
per-result/cumulative-byte and cooperative deadline limits remain in force.

Portable tests exercise real calculation and result validation using scripted
model decisions to isolate the state machine. These tests do not prove actual
model selection quality. The separate actual pinned-model acceptance probe must
choose calculate and pass real evaluation, receipt ordering and answer checks.
Native/iPhone execution remains unverified until the corresponding gate/device
test. No release-readiness claim follows from this source checkpoint.
