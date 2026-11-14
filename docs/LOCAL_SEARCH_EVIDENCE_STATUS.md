# Useful offline search evidence

Candidate only. Native Swift/SQLite/UI execution remains unverified.

Conversation and saved-memory tools now return a bounded passage around the first literal case/diacritic-folded match, rather than the first160bytes regardless of where the fact appeared. Excerpts stay contiguous original Unicode scalars, at most160UTF-8bytes; small texts are returned whole. Long matching phrases can be shortened and existing excerptMayBeTruncated remains explicit. The original records are unchanged. Conversation lookup uses stable POSIX folded matching, rejects blank-only queries, and title-only matches return title evidence instead of an empty excerpt. This is lexical lookup, not semantic reasoning or a guarantee that every relevant fact is found.

Conversation result schema now accepts valid escaped control characters verbatim, keeping field byte limits and strict Unicode. Real portable tests demonstrated the permitted worst-case10-result schema can exceed16KiB (16,412bytes), so only conversation-result JSON has a20KiB cap; the outer envelope remains32KiB. Native output matches that cap. Memory remains16KiB. Strict query/command validation is unchanged.

Eight native excerpt regressions and one actual-store/tool late-match regression are authored but uncompiled/unrun. Three new portable reducer tests exercise control-heavy and escaped evidence through record/report/recovery plus Unicode byte limits. Full portable results:128Python/70agentJS/39VMJS pass. Source review also fixed a short-text late-match edge so the existing truncation flag stays accurate. No paid CI or release.

Latest validation update: the Foundation-only algorithm tests now compile and pass under actual Swift6.0.3 on Linux (25 tests combined). Earlier unrun statements describe the prior gate. iOS integration/UI/device tests remain unrun. See FOUNDATION_SWIFT_VALIDATION.md.
