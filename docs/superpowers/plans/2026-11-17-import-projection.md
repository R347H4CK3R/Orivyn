# Bounded import projection implementation plan

Goal: remove whole-record Foundation object graphs while preserving conversion behavior and originals.
Approved approach: strict bounded scanner validates all JSON, selectively projects the fields consumed by archive conversion/identity. Unknown subtrees are validated but not retained. Foundation decodes bounded scalar/opaque values to preserve NSNumber/null/canonical JSON behavior. Selected-key duplicates reject, including escaped aliases. Mapping duplicates reject. Unknown duplicate keys are ignored, matching their lack of semantic impact.

1. RED duplicate selected-field tests against old stream (observed 644 tests, 6 assertion failures before implementation; narrow unknown duplicate fixture to selected-only rule).
2. Implement scanner/projection beside ChatGPTRecordStream; public validate and project APIs, budgets/depth/cancellation, no unbounded DOM parse.
3. Reuse projected dictionary across ArchiveRestoreService identity and conversion; keep data conversion wrapper for existing callers. Original archive retention unchanged.
4. Add malformed unknown-subtree syntax, privacy/routing/null/timestamp, escaped duplicates, opaque bounds and differential projection fixtures. Run full Foundation suite and source parse checks.
5. Measure original object-dense fixtures using production scanner/converter. Save exact source evidence. Review independent from implementer and native platform testing required before release.

Risks: new strict JSON scanner; resource limits may reject formerly accepted but unsafe shapes without losing originals. Linux measurements do not establish iPhone memory thresholds. Full ZIP/SQLite lifecycle outside this isolated patch.
