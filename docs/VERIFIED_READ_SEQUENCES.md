# Explicit local read sequences

The existing deterministic proposal router now accepts `read app info`/`read app information` and clauses separated by `and`, `and then`, `then`, semicolons or newlines. Search queries remain double-quoted exact data. All clauses must match a supported local read in full; unsupported, negative, conflicting or incomplete clauses never produce a partial proposal.

This is not general model autonomy and does not fix the experimental model's wrong-tool failures. It extends the existing user-reviewed, four-tool local plan. Nothing runs while parsing. The user must still review and confirm. Execution uses the existing canonical order: app information, installed models, conversation search, memory search. The proposal explicitly discloses that this is not typed order. Results are exact bounded structured evidence, not a generated summary. Search result limits remain unchanged.

Verification: red tests before implementation; 95 JavaScript agent tests passed, including a router-to-plan lifecycle test proving that app information alone cannot complete a two-read plan and that installed-model evidence remains distinct from the assistant name. Tests use explicit synthetic native-tool results and do not establish iPhone operation. Native UI/device/IPA validation still required.
