# Plugin approval model correction

The 194-test artifact (archive-gate14211224833.zip) recorded 191 passes
and three failures. The actual local memory, Automatic selection and coding probes passed.
The fourth conversation probe did not: its answer incorrectly allowed skipping exact-call
review for policy-compliant calls. The strict oracle rejected it correctly. Broker review
remained enforced; no plugin execution or bypass occurred in this probe.

The instruction used ambiguous `by you` alongside a capability distinction between local
suggestion and execution. This change explicitly names the human user as reviewer and
Jarvis as unable to run without exact name-and-argument review, with no policy-compliance
exception. It does not claim to prove the model's internal cause. Unrelated redundant
prose is shortened to retain headroom in the unchanged local tokenizer budget. Coding,
no-echo, inventory, actual-receipt and permission boundaries remain.

The same four actual-model prompts and strict approval oracle are unchanged. Local source
checks cannot establish model compliance. A new native inference run must verify this
candidate; the prior 191/194 outcome remains a failed gate. No deterministic canned answer
was substituted for inference and no guard or approval requirement was relaxed.

Final local validation: 602 exact-source Foundation tests passed. This only checks source
and deterministic behavior; the repaired actual-model answer is still unverified.

Integrated rerun preparation: independent review confirmed the exact 200-test gate
(194 previous selectors plus five arithmetic loop methods and one real-model
calculator method). The original four conversational probes and their strict
approval oracle remain unchanged. Exact-source portable validation passed 602
Foundation tests and 154 Node tests. Two Python wording guards initially failed
because they matched removed prose; equivalent identity, code-as-text, no-false-
execution, local-proposal-only and user-review assertions were independently
reviewed. The complete Python suite then passed 278 tests with its one existing
skip. These are not native/model approval correctness results.
