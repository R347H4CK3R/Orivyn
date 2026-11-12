# Bundled app self-knowledge

The provider prompt now includes a bounded, versioned `OrivynCapabilities.json` manifest plus the running bundle version, build and selected provider. This is conservative product metadata, not a source checkout. It does not expose credentials, automatically contact GitHub or claim access to the private repository. Missing, oversized or unsupported manifests fail closed without guessed capabilities.

This supports explanation and bug-report drafting. Autonomous repository inspection, repair, build and publication are **not implemented** by this change. Native VM and general visual understanding remain explicitly unavailable in product chat. Conditional features still require actual device availability, permissions, configuration and successful execution.

When shipping a changed capability, update the manifest only after its own verification. Runtime bundle version is read instead of hardcoding the target 1.0.0 as an achieved release.

Verification in this Linux environment: manifest tests failed before addition, then all 75 script tests passed. Native XCTest source and provider integration assertions are added but have not run here because Swift/Xcode is unavailable. The parent must run them in the next native simulator gate. No IPA or source publication was performed by this step.

## Prompt budget correction

The initial full-manifest prompt was rejected by the actual 2,048-token local runtime: it permits at most 512 system tokens while reserving 1,024 for output. Across all nine cached catalog models, the default expanded prompt measured 664 Qwen tokens or 717 SmolLM tokens. This was a real tokenizer result, not an estimate.

The prompt now includes a compact boundary summary instead; the full manifest stays bundled for local inspection. `test_self_knowledge_budget.py` renders the actual Swift literal template, runs the pinned tokenizer on available catalog weights, and requires at most 384 tokens for the default system prompt. This preserves at least 128 tokens of system allowance for customization. Existing runtime validation still rejects oversize custom instructions/memory rather than silently dropping them. The test explicitly skips when tokenizer/weights are absent; CI should additionally exercise the full AppModel request through native inference.

After correction, all 76 script tests passed, including all nine real tokenizer checks: seven Qwen variants measured 304 tokens, two SmolLM variants 325 tokens. The default prompt is 1,360 characters, leaving 7,640 characters in the Apple provider's 9,000-character input policy. Native simulator inference remains a separate required check.

## Native verification update (2026-11-12)

The focused simulator gate at private commit `780b2a4` passed all 16 selected native tests (12 AppModel and 4 AppSelfKnowledge), including `testRealLocalModelAcceptsKnowledgeAtProductionOutputReservation` with the actual downloaded local model. The separate BIOS subgate failed; `KNOWLEDGE_STATUS=0` does not mean the aggregate workflow or virtual desktop passed. Evidence was retained from Codemagic build `6af63eb710a05158d8122bce`.

Current local regression check: 78 Python tests pass, including the nine real tokenizer budget checks. These results supersede the earlier native-unrun notes above only for this selected self-knowledge gate. Physical iPhone tests, autonomous private-repository repair and a complete virtual desktop are still unverified/not implemented.
