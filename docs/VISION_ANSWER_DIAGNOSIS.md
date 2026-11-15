# Vision answer-generation diagnosis

Six additional real-model probes used the same pixels as frozen cases 02 and 08, with the production-pinned SmolVLM2 2.2B Q4 model and the existing Linux diagnostic library. This does not re-establish latest-source binary provenance or verify iOS.

For case02, a description correctly placed the blue circle to the right of the orange square; direct questions correctly identified the circle on the right and square on the left. For case08, the model described four circles around one square and correctly counted one orange square, but answered five when asked specifically for the number of blue circles.

These observations point to question-sensitive answer generation rather than a simple mirrored-image input problem. They do not prove every image preprocessing path correct. The original frozen acceptance cases still fail; none were changed, replaced or relaxed. Raw outputs, questions and resource reports are retained in Diagnostics/VisionProof/QualityV1/RESULTS_DIAGNOSTIC_QUESTIONS.json.

A validated stronger model or multi-stage workflow may be needed. Neither has been implemented or accepted by these probes. No new production vision prompt or post-processing correction was introduced.
