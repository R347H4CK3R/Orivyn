# Two-pass vision experiment

The production-pinned SmolVLM2 2.2B pair was tested on the same ten frozen QualityV1 images/questions. First ask for a scene description, then present that description with the same image and original question. No expected answers were supplied and no answers were repaired.

Only 5/10 cases completed both stages and matched. The existing single-pass baseline remains 8/10. The experiment retained both original failures and regressed spatial and transcription cases. case10's caption call returned status 8, so a correct second-stage answer does not count as complete. A process interruption (exit 137) split execution after four completed cases; the remaining six ran in a fresh process. The first-phase resource report was not retained, so no full two-stage resource-cleanup assertion is made.

A separate text-only Qwen3 1.7B Q4 diagnostic correctly inferred right from case02's correct caption. This is one supplied-description inference, not an end-to-end vision improvement. The generated captions elsewhere hallucinated objects/counts and text; caption reasoning cannot recover missing or wrong visual facts reliably. No production vision change is integrated.

Exact prompts, outputs, hashes and scoring are in Diagnostics/VisionProof/QualityV1/RESULTS_TWO_PASS_EXPERIMENT.json. Frozen cases and baseline results are unchanged.
