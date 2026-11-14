# Experimental agent evidence-exposure guard

The reducer previously accepted an answer after one successful tool even when only its first 256-byte page had reached the prompt. It now records contiguous exposed byte counts for each saved result. A premature answer selects the first unread evidence page instead of becoming a completed answer; this transition consumes the existing internal-read budget, not a native-tool call. Noncontiguous page reads cannot conceal a gap. Budget exhaustion fails explicitly with no accepted answer. Legacy states gain conservative zero coverage and one durable migration revision; already-terminal answers are retained as historical records.

Exposure is not comprehension. Each native generation is still a bounded prompt, not evidence of model memory or semantic correctness. This guard does not make tool choice reliable, prove answer truth, expand permissions, or execute additional native tools.

Verification:
- New regression failed before fix (premature answer wrongly marked answered).
- All 90 portable agent JavaScript tests passed, including UTF-8 gaps, migration, bounds, six maximum results and read-budget exhaustion.
- All 143 Python repository tests and 39 production VM JavaScript tests passed.
- Independent read-only review found no blocking issue in the narrow reducer guard; native/device validation remains outstanding.
- Actual cached Qwen2.5 1.5B Q4_K_M / llama.cpp b9049 CPU2, context2048 regression repeated once, using synthetic fixture tools only: multi-tool case still failed (skipped model lookup and misidentified version as model); tail case no longer falsely completed but failed strict JSON parsing after automatic paging (unterminated string). No retry or parser relaxation concealed these failures.
- Native iPhone/JavaScriptCore testing not run. No release-readiness claim.

Raw current-source model evidence: sibling `Orivyn-local-agent-smoke/paging-completion-guard`. Server stopped in finally.
