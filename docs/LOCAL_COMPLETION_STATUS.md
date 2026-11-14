# Local inference completion integrity

Candidate only; native compilation and real iPhone inference remain unverified.

Review found the llama loop reported success after exhausting its token limit even without an end-of-generation token. It now requires an observed model end token before successful completion. Exhaustion throws a specific error after preserving already-streamed text. Existing AppModel error handling marks that response failed and retains it; voice only receives successful final answers, so an exhausted response cannot be reported as a successfully finished voice reply. This does not extend context, guarantee a model ends correctly, or automatically continue truncated output.

A second issue silently omitted later nonempty attachments when the first consumed the4,000-character budget. The prompt now includes the number of additionally omitted attachments and tells the model not to claim it read them. This is disclosure, not a guarantee of model obedience or full-document analysis. Existing original attachments remain stored.

Two portable wiring guards failed before implementation and now pass. Full portable suite:125 Python,67 agentJS,39 VMJS. Native regression added for exact-budget multi-attachment omission; existing real-model test extended with a one-token grammar-constrained response that must throw generationLimitReached. Native tests are uncompiled/unrun; weights and Apple toolchain still required. No paid CI, release or full1.0 completion claimed.
