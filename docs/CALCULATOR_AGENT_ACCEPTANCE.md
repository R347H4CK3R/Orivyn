# Calculator tool integration and semantic integrity

The model-driven local agent can request calculate with one expression string. Its reducer validates exact argument keys, nonempty bounded UTF-8, durable pending/result transitions and the existing six-call cap. The bundled grammar exposes only this arithmetic tool, not code execution. Native dispatch invokes the same parser as Calculator.

## Real failure found and guarded
An initial actual Qwen2.5-0.5B test dropped parentheses: (12 + 8) / 4 became 12 + 8 / 4. The native parser correctly computed14 for the changed expression, but that was wrong for the user goal. Raw failure is preserved in calculator-model-path.

Native agent dispatch now requires the persisted user goal. LocalCalculatorRequest accepts only an explicit arithmetic goal, optionally starting Calculate/Please calculate; both original and proposed expressions must parse. It compares only whitespace/operator-glyph normalization, never drops parentheses, changes numbers or silently repairs a mismatch. Word problems and extra instructions are unsupported. Mismatch stops the task with a direct-Calculator fallback, not a fabricated answer.

## Actual combined path
calculator-agent-2 used exact production engine/grammar/JS reducer/Swift task store/parser with Qwen2.5-0.5B. It copied a schema placeholder instead of the expression. The guard rejected it and the task was preserved as failed; this is not an end-to-end success.

calculator-agent-15b used Qwen2.5-1.5B with the actual reducer prompt and actual native-session system text. It chose the correct calculator request, persisted the running intent, passed exact-expression validation, received native result5, returned answer5, passed reducer validation, persisted and reopened the final record. This is one successful host scenario, not general agent reliability. Node hosts the production reducer here; native JavaScriptCore/SwiftUI are not executed.

calculator-agent-1 was a test-driver startup failure from an assumed Node location. The runner now explicitly resolves and records its host Node executable. No production behavior depended on that path.

## Verification boundaries
278 Foundation XCTest tests pass, including expression integrity and adapter tests. 74 Node tests pass. The baseline engine regression remains independently recorded. The test runner preserves source/runtime/model hashes and raw decisions. Missing iOS compilation, native tool-session/device validation and model semantic limitations still block full release acceptance.

## Independently revalidated evidence display
The task view now decodes each recorded tool's arguments and shows successful calculator evidence separately from the unverified model answer. Before displaying it, the Foundation helper validates the exact result schema and recomputes the original expression against the saved user goal. Wrong results, changed expressions, extra fields, failed/non-calculator events and malformed or oversized JSON do not receive the evidence display. This verifies bounded approximate arithmetic, not transcript authenticity or the model's interpretation. Raw model prose is preserved even when contradictory.

The actual-model harness now requires the complete trimmed answer to equal `5`, rather than merely containing that number; it also decodes the production snapshot and revalidates its saved evidence. The prior fixture happened to produce exactly `5`, but the weaker assertion is no longer used. Native SwiftUI rendering remains untested.

Verified current evidence: `calculator-evidence-final` passed285 Foundation tests;135 Python tests and74 agent Node tests passed. `calculator-evidence-real` successfully ran actual Qwen2.5-1.5B with exact answer `5`, production snapshot decoding and independent evidence recomputation, then durable reopen. The first full Foundation run failed only a test's assumed fraction formatting; the corrected test checks actual adapter output and numeric value, with no production formatting change. Initial logs were preserved. Private source checkpoint:36c5dec30dfc396f79fc83703139f2b38fc42a0e. No new IPA or production release.
