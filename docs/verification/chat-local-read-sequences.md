# Explicit local read sequences in normal chat

Normal Send can perform up to three distinct allowlisted local reads requested in
the current composer, without opening a review screen or contacting a model.
For example: `list installed models; show app information; search saved memory for My Boat`.
Explicit `then` or `and then` delimiters are also supported. A memory search must
be last; its case and ordinary punctuation are preserved as inert query data.
Ambiguous multi-command syntax, multiline/code/handoff envelopes, attachments,
duplicate reads and unknown operations do not authorize automatic execution.

The only tools are `list_models`, `get_app_info`, and `search_memory`. This is a
bounded deterministic subset, not general natural-language agent orchestration.
No retrieved history, model output, server schema or imported result grants scope.
External plugin calls still require exact review; plugin installation, external
writes and arbitrary code execution are not added.

Reads execute sequentially as the consumer requests stream elements, with no
background producer continuing after the consumer stops. Each result is bounded
to 4096 bytes, and cumulative evidence to 12288 bytes. Only completed steps receive
completion labels. Errors/cancellation stop later steps; prior emitted evidence
remains in the conversation with the existing failed/interrupted message state.

Isolated component suite: 547 portable Foundation tests passed after the query
compatibility repair. Three new native AppModel integration tests are authored
but require the combined native gate. This document does not claim iPhone or
actual-user-archive verification or broad autonomous capability.

Combined integration validation: 554 portable exact-source Foundation tests passed.
The next public synthetic-only gate requires all 125 selected native/simulator
tests and no skips; this is a requirement, not a claimed native result.
