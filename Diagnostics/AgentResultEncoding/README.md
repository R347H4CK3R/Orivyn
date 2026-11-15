# Tool-result encoding diagnostic

Two frozen synthetic failing post-search prompts are compared with exactly the same prompts except nested result JSON strings are decoded to objects. Grammar and model are unchanged between arms. This diagnostic constrains conversation IDs to the fixture ID; it is not a general-autonomy acceptance test or a production change.

The workflow builds a fresh CPU CLI at pinned llama.cpp b9049 and records its hash alongside the pinned Q4 model hash. Its binary is not assumed identical to the local recovery binary. Successful job execution means observations were collected, not that decisions were correct. Inspect every result and preserve failed/timeout runs. An improvement would require independent holdouts and real app regressions before integration.

The previous local attempts exited 137 before any completed decisions. Their cause is unknown. This separate free public Ubuntu runner avoids relying on that interrupted environment; it is not an iOS test.
