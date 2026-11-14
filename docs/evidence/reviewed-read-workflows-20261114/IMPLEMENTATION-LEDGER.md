# SDD ledger — plan: docs/superpowers/plans/2026-11-14-reviewed-conversation-workflow.md
Base98920fd. Own backend; root UI; separate independent holdouts.
Pre-flight Task1→2→3: stable LocalReadPlanProposal(goal,plan), LocalReadPlan kind String and optional title/messageIndexes. Version2 readPlan+approvalRevision0, version1 unchanged.
Ruling: NFC lowercase exact titles; ambiguous or incomplete searches fail read workflows. Search-only accepts an exact bounded search result and discloses partial flags.
Ruling: interrupted contracted operation fails on resume rather than replaying an uncertain read; preserved history stays inspectable.

Backend Tasks1/2 complete locally; root owns UI Task3; independent Task4 holdouts pending.
Ruling: explicit user-selected workflow kind approved by root after three wrong-kind model proposals; title/query/indexes remain model-proposed and user-reviewed.
Ruling: exact current reviewed search recreation protects search-only excerpts; full title metadata avoids clipped-title ambiguity without changing generic search.
Ruling: installed static stdlib used to execute unmodified production Session after dynamic Observation linkage failure.
Verification:134 JS,423 Foundation,198 Python(1skip),46 native grammar, unit session lifecycle passed; five actual proposals rejected, no workflow or accuracy pass.
