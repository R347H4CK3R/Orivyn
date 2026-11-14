# Deterministic verified-local-read candidate

This mode is separate from experimental model autonomy. The user chooses exact operations: app metadata, installed model names, and/or a conversation search query. No language model interprets the goal, chooses a tool, summarizes evidence or writes an answer. This does not satisfy unrestricted autonomous tasks or self-repair.

The trusted reducer creates a fixed plan of at most three reads, persists a unique running intent before native dispatch, validates the result schema, and retains the entire returned structured evidence. Every report says whether the selected plan is complete and includes explicit source limits. App identity and model identities remain separate typed fields; later matching records are retained rather than reduced to a model prompt prefix.

Native integration uses the same real read-only app-state tool implementation as the experimental mode, but does not load inference models. A separate app-owned execution identity blocks overlapping task mutation across screens. Durable records are private/protected, have monotonic revisions, preserve partial evidence, and require explicit recovery/resume. Archive/restore preserves data and refuses overwrite/resurrection. Six total read attempts are permitted, at most three successful reads.

“Verified” means the selected local read returned schema-valid data. It does not establish that stored conversation content is true or that the application is bug-free. Results remain bounded by the native source: first24 capability entries,10 installed models,500 searched conversations and10 matches; names/excerpts may be shortened and limitations are disclosed.

Evidence:14 actual-code deterministic JavaScript tests pass, including combined app/model identities, tail records, malformed results, cancellation/recovery, different retry IDs and bounded attempts. Total agent tests39; repository Python92; VM JavaScript39. The native bridge, actual AppModel/no-inference regression and UI have not been compiled or run. Native validation remains a release gate. No model-smoke failure was reclassified as successful; both tested model families remain unreliable for the experimental autonomous loop.

Independent source review found no definite schema/API/compile mismatch, but caught stale Saved plans after cancellation/error. Persist now upserts the displayed record immediately; native assertion added. This remains source-review evidence, not compilation.
