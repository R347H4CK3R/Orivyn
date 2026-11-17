# Exact plugin literal fidelity repair

## Evidence and scope
Build23 native run44100215492 passed313/314 with no skips. The actual pinned model changed one digit of an explicitly quoted exact search phrase. The same corruption reproduced in the pinned Linux production provider. Schema type validation cannot establish literal fidelity. This was a proposal-only test, not evidence of external execution. Preserve the original goal, exact UTF8 equality, failed artifacts, and released build22.

## Reviewed architecture
Use a representation-only source reference for a narrowly recognized direct-user exact phrase. The model still proposes tool and root argument field; the adapter copies the decoded original JSON string exactly. This is not semantic field inference, authorization, arbitrary string correction, or execution. Existing original schema validation and user review remain mandatory.

- Bound and independently extract one unambiguous literal from the original direct goal. No model/history claim may enable the mode.
- Exact mode is narrowly binding-only: arguments must be empty and a separate top-level literalBindings table names unique declared root string properties. Only reference0 exists. Calls requiring mixed or nonliteral values are unsupported in this mode, rather than silently corrected; ordinary non-exact requests retain their existing route.
- Reject raw string values recursively, unknown keys, duplicate/conflicting bindings, out-of-range references and invalid schemas. Never fall back to raw copying after an exact-mode failure.
- Resolve references, validate the complete result against the original selected tool schema, then publish only ordinary resolved arguments to the existing review path.
- No-exact-literal goals retain the existing path. Ambiguous exact-literal intent fails explicitly.
- Constrained output may improve protocol compliance, but parser validation remains authoritative. Grammar must not deterministically choose the intended tool or field.

## Experiments
1. Baseline production provider reproduced the native digit mutation.
2. Prompt-only reference protocol emitted both arguments.query and a query binding. Correctly invalid; do not drop or repair the conflict.
3. Constrained protocol scratch probe passed on the same failing goal without forcing tool/field or retrying. This is feasibility only, not production proof.
4. First generic production grammar admitted an extraneous numeric body field; original schema correctly rejected it. Preserve this failed proof. Narrow the exact mode to binding-only instead of permitting irrelevant numeric arguments or dropping them.
5. Dedicated request mode, strict binder and narrowed engine grammar implementation underway; full production-model and adversarial validation pending.

## Verification before release
- Red/green unit tests for source extraction, UTF8/escaped data fidelity, collisions, duplicate/unknown fields, injected protocol text, nested raw strings, ambiguity and unsupported schemas.
- Typed mode isolation and engine grammar admission tests; original output bounds and cancellation retained.
- Actual pinned-model proposal with unchanged goal and exact equality; evidence explicitly distinguishes model selection from adapter copying. No retries or external calls.
- Independent source/security review, full Foundation and Python suites, updated exact native composition, all required native/host/resource/package gates.
- Guarded publication and fresh public artifact/catalog verification only after all gates pass.
