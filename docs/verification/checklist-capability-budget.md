# Reviewed checklist capability evidence budget

The 180-test native gate exposed a deterministic integration regression: detailed
`get_app_info` output fit its 4,096-byte tool limit but exceeded the reviewed
checklist's cumulative 3,500-byte prompt limit. The reducer correctly retained the
first result and failed closed before the second decision. The resume test then
timed out waiting for that decision. This was not evidence of a resume race.

Only version-3 reviewed checklist `get_app_info` now requests 1,024 bytes from the
existing result encoder. It retains whole capability records including their
prerequisite details; omitted records are explicitly counted. Top-level metadata
restrictions remain. This is a partial catalog, not an assertion that omitted
features are absent. Normal conversational reads retain their 4,096-byte limit,
and the full bundled manifest is unchanged. Larger cumulative result sets can
still fail closed; this is not a universal context-fitting solution.

Verification:
- Actual bundled metadata and production JS reducer regression observed failed
  before the cap, then passed with the cap: 19 focused tests passed.
- Full Node suite: 154 passed, zero skipped. An initial sandboxed invocation could
  not create temporary fixtures; the authorized rerun passed.
- Strengthened the existing native resume test with actual encoder output bounds,
  exact retained detail/status comparison, omission accounting and prompt bound.
  All original wait, resume, ordered-history and answered-state assertions remain.
- Swift syntax parse passed. Native execution and Apple typecheck remain pending.
