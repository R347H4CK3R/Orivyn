# Tokenizer-aware local attachment fitting

Candidate implementation only. Native compilation/inference remains unverified.

Local inference previously expanded attachments to4,000characters then failed when even the newest question could not fit the2,048-token context. Engine preparation now renders original messages using six nonzero excerpt budgets (4000,2000,1000,512,256,128), applying the real model tokenizer to the complete template/system/message prompt at each attempt. Complete older messages are trimmed by the existing policy before reducing excerpts. The newest typed question is never shortened. Only promptTooLong permits retry; unrelated errors propagate. If the smallest excerpt still cannot fit, the request fails rather than silently using zero attachment evidence.

Excerpts remain leading prefixes, not semantic retrieval; short prefixes may contain only OCR provenance/header text. Multiple attachments can still be omitted when the per-message aggregate budget is exhausted, with explicit disclosure. Composer now warns that models may receive shortened excerpts and points to offline extracted-text search. Original attachments/history are not mutated. This is not full-document understanding or an answer-quality guarantee.

Nine native regression methods authored: shrinking with typed preservation, old-turn priority, nonzero floor, unrelated-error propagation, Unicode/clamping/omission, typed-only rejection, supplied dense-count handling. Native tests are uncompiled/unrun. Two portable wiring checks failed before implementation and now pass; full portable suite127Python/67agentJS/39VMJS passed. No paid CI or release.
