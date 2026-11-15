# Complete workflow diagnostic

99f6157 / run 43674049534 failed all four cases before executing tools. Every raw output contained search plus a read using invented ID 1. The strict one-call parser correctly rejected each output. Earlier 4/4 next-decision results started after completed search and did not cover this initial step.

Follow-up retains rejection of multiple calls and unauthorized IDs. It aligns advertised availability with the app's existing policy: read_conversation is absent until a completed search returns IDs; returned IDs are enumerated thereafter. The system requests exactly one call and waiting for its result. All four fresh-marker SQLite cases are repeated. This is a diagnostic policy/format adjustment, not production integration. The complete Swift reducer/native app remains unverified.
