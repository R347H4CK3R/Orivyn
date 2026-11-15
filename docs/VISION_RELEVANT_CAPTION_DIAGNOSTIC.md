# Question-focused caption diagnostic — rejected

On 2026-11-15, the existing Linux vision bridge and pinned production SmolVLM2 2.2B Q4 model/projector ran all ten frozen synthetic images. The caption instruction was the same template for every case: “In one short sentence, describe visible evidence needed for this question: [original question] Do not infer hidden details.”

All ten native calls returned status 0, with reports retained alongside both the diagnostic and original question and pixel hashes. This is a diagnostic caption stage, not the frozen direct-answer gate or a completed two-model evaluation. No iOS/device verification is implied.

The original two defects remain: case02 describes the blue circle as above the orange square instead of right; case08 reports five circles instead of four. The planned text-only answer stage was not run because it cannot reliably recover visual evidence absent from those captions. No production behavior or acceptance oracle was changed.

See `evidence/vision-relevant-caption-20261115.json` for complete outputs and `evidence/vision-relevant-caption-20261115.py` for the exact in-memory diagnostic script. The shared library is an existing Linux diagnostic binary; its hash is recorded, but it was not freshly rebuilt from the current app source.

## Short generic caption follow-up

A question-independent prompt requested one sentence of at most 20 words. All ten calls completed without truncation, but cases01–04 omitted spatial relationships, case07 hallucinated a cartoon face, and case09 described a tree rather than MAPLE 47. Case08 described four circles, but the broader regressions reject this as a replacement. The text stage was not run. Full reports and the exact script are in `evidence/vision-short-caption-20261115.json` and `.py`. Production behavior remains unchanged.
