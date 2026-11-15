# Grounded-answer workflow evidence

Initial full workflow run 43674049534 (99f6157) failed 0/4: every model response contained a search followed by a read with fabricated ID 1. The strict parser rejected the whole response before executing tools. This exposed a gap not covered by the earlier 4/4 post-search next-decision test.

Follow-up 43674518501 at 11af76fd69044b68f653054277f25901e0285cc1 passed 4/4 after applying state-aware advertised availability: no read tool before a completed search, only returned IDs afterward, and one call per response. Each case executed actual SQLite fixture search, read the requested message, and returned a fresh unpredictable code. Two cases were new holdouts. Downloaded artifact 14145484650 confirms exactly search -> read -> answer for every case. Prompt tokens ranged 656–1227; with 384 output tokens each fits 2048. Raw failures and successful prompts/outputs are preserved.

This is pinned real-model inference in a bounded Python/SQLite diagnostic executor. It does not verify the production Swift reducer, engine bridge, permissions UI, device behavior or general autonomy. A separate portable Swift adapter is under development; no production protocol change is integrated yet.

Integrated source 86c3717 passed 1,024 native tests (5 skipped, zero failures) and unsigned device build in run 43673278573 core job132687802730; portable run43673278575 also passed, including 139 persistence tests. Native inference still fails the unchanged general-agent case; remaining UI jobs and picker follow-up have separate status.

App sync candidate a3f7da4 adds receive ownership/reconciliation but is not integrated. Review found a preflight retry gap. Isolated test commit75727fb extends to seven native cases to reproduce it and cover cancellation/real attachment files. Do not treat this as complete automatic sync or as part of published build8.
