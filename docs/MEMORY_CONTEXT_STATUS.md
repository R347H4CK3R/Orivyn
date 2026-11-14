# Bounded offline memory context

Before this change, every saved memory was concatenated into every system prompt. A large library could exhaust local context or make remote context trimming fail before a response. Normal chat generation now selects bounded saved-memory excerpts instead.

The pure local selector scans at most500 notes, examines at most4096 UTF-8 bytes per note/query, ranks literal folded-word overlap then recency/stable order, and emits up to eight excerpts. Disclaimer and delimiters count toward the hard cap. AppModel uses512 bytes for local/system providers and1024 bytes for remote. Original notes are never altered. This is bounded lexical retrieval, not semantic search or a guarantee of choosing every relevant note. It does not guarantee total prompt fit; the provider still applies its tokenizer/context checks.

Saved memory UI discloses bounded selection and reports the latest prepared selection's included/total/scanned counts and omissions. The label says prepared context, not that a provider necessarily accepted it. Saved notes remain user context, not higher-priority instructions. Existing remote-provider disclosure still applies to selected notes.

Nine native selector regressions cover byte ceilings, Unicode, ranking/fallback, immutability and scan bounds. One native AppModel test verifies a large stored library produces bounded relevant context at the actual provider boundary without deleting notes. All ten are authored but uncompiled/unrun. Two portable wiring guards observed preimplementation failures then pass; full portable results:121 Python,67 agent JS,39 VM JS. No paid CI, native/device success or release is claimed.

Latest validation: the actual MemoryContextBuilderTests and MemorySearchTests now compile and pass with Swift6.0.3 on Linux, alongside stored-memory schema round-trip tests. The AppModel/iOS integration test remains unrun. See FOUNDATION_SWIFT_VALIDATION.md for exact scope.
