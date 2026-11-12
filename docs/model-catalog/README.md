# Free downloadable model catalog, reconstructed candidate

This catalog was reconstructed on 2026-11-12 from the preserved design and fresh official publisher evidence. It is not a byte-identical recovery of the lost local Orivyn candidate. The independently recovered base is `f4ac85877bfa707061a3c6cd902412be65cff34e`; the repository's original branches were not overwritten.

## Included choices

Nine downloads cover eight distinct base models, not nine unrelated model families:

| Model | Precision choices | Purpose | Suggested device RAM |
| --- | --- | --- | --- |
| SmolLM2 360M Instruct | Q8_0 | Small everyday tasks | 4 GB |
| Qwen2.5 0.5B Instruct | Q4_K_M, Q5_K_M | General chat | 4 GB |
| Qwen2.5 Coder 0.5B Instruct | Q4_K_M | Code explanations/drafts | 4 GB |
| Qwen3 0.6B | Q8_0 | Experimental reasoning | 4 GB |
| Qwen2.5 1.5B Instruct | Q4_K_M | General chat | 6 GB |
| Qwen2.5 Coder 1.5B Instruct | Q4_K_M | Code explanations/drafts | 6 GB |
| SmolLM2 1.7B Instruct | Q4_K_M | General chat | 6 GB |
| Qwen3 1.7B | Q8_0 | Experimental reasoning | 8 GB |

All are ungated, officially published GGUFs with Apache-2.0 terms at the recorded immutable revisions. No accounts, API keys, pay tiers, subscription SDK, or automatic model downloads are added. The app remains free; an explicitly configured optional external endpoint may charge separately. Imported GGUFs remain possible within the existing 2 GB limit, but their provenance/license/runtime compatibility is the user's responsibility.

## Provenance and regeneration

- `catalog.json`: curated choices, exact byte lengths, SHA-256 values, immutable revisions, upstream license URLs/digests and iPhone guidance.
- `publisher-evidence.json`: separately fetched official Hugging Face pinned API metadata and license/model-card reads. Where no standalone license file exists, the pinned model card's Apache declaration is recorded; it is not misrepresented as a full license file.
- `template-evidence.json`: fresh exact-file GGUF architecture/template checks using the bundled runtime version's C API, `llama_chat_apply_template`, on system+user messages. These do not prove inference or quality.
- `recheck-evidence.py`: explicit operator-run reproduction, not run by the app or automatically in CI. It fetches metadata prefixes (up to 8 MB each), not whole weight files. It verifies the b9049 Linux binary archive SHA-256 before loading its C API.
- `scripts/model_catalog.py --check`: offline validation of safe paths, sizes, unique IDs, licenses, cross-evidence pins and generated Swift freshness. Ordinary generation requires omitting `--check`.

The app downloads the pinned weight URL only after the person selects Download. Existing streaming byte limits, SHA-256 checks, atomic installation, HTTPS checks, cancellation and before-inference integrity checks are preserved. No weights are bundled in the shipping IPA.

## Efficiency and limits

One shared `LlamaEngine` belongs to `AppModel` so changing providers does not retain a separate loaded weight set per model. Existing 2,048-token context, bounded output, batch size 128, memory-pressure/background unload and model switching remain. Behavior and saved-memory context now has a real-tokenizer budget; oversized preferences produce an actionable error instead of silently dropping instructions.

Installation reserves roughly twice the file size plus 100 MB. RAM values are conservative guidance, not device measurements or a promise that iOS will allow that much app memory. Smaller files are usually the practical iPhone choice. Search, purpose filtering and smallest-first sorting do not affect the separate active-download/cancel controls. A DEBUG-only controlled UI regression covers that boundary without pretending to download or infer; Release verification rejects its marker.

Qwen3 can spend the short reply budget on thinking text. It is labeled experimental. No vision, tool execution, safe autonomous actions or reasoning quality is inferred from the model name. Small models can hallucinate.

## What was actually verified

Fresh reconstruction checks: official metadata/license reads for eight repositories; all nine exact GGUF templates accepted by pinned b9049; catalog and package Python tests; generated-source freshness and whitespace checks. Native compile/UI/device-package results belong to the separate build report and must be verified before delivery.

Historical retained reports describe eight full-file SHA/size checks and Linux CPU inference probes for the lost candidate. Those logs/source bytes were not recovered and are **not** presented as fresh execution evidence. No physical-iPhone RAM, thermal, latency or battery benchmark has been performed for this catalog. Broader variants should be admitted only after repeating publisher/license/template checks and practical device testing, not merely to increase a count.
