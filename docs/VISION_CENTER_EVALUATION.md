# Center-preserving crop: not accepted as a general fix

Run43680221713 evaluated source c51622587180f24f1c1ba96bc62ad85877abee3e with pinned SmolVLM2-2.2B Q4/f16 on Linux CPU. Both baseline and candidate scored8/10 on unchanged frozen acceptance; case02 still returned left and case08 still returned5. Baseline strict expanded holdout score was12/18; candidate14/18. The candidate improved one zero-circle case and changed a boxed landscape answer from valley to river, but did not fix the remaining right/bottom position or mixed-shape counting failures. No catalog, release, or main-branch change is recommended.

All56 real inferences completed with status0, one image chunk, acknowledged closure and zero tracked native handles. This counter is not a heap-leak proof. Full raw responses, hashes, model manifest and immutable test definitions are retained in docs/evidence/vision-center-evaluation-20261115.json, artifact14148277870.

The newly authored holdout includes10 shifted geometry/count cases,4 absolute image-half questions and4 full-frame/letterboxed variants of2 pinned natural photos. It is a small diagnostic, not broad natural-image acceptance. The landscape question asks what is between mountains; valley is plausibly a valid answer, although the predeclared narrow water/river/lake/fjord set rejects it. That scorer was not weakened after observing outputs, and its strict count must not be presented as unambiguous semantic accuracy.

Symmetric cropping preserves original center/axes but still changes distances to image edges and the amount of whitespace. It is unsuitable as an unconditional general image-analysis preprocessor without an original-coordinate-aware design. The earlier foreground-centered proposal additionally moved off-center objects and was rejected without a completed candidate evaluation. The original frozen acceptance and all failures remain unchanged.

No iOS simulator, physical iPhone, UI, offline-device, memory/thermal or broad autonomous-tool acceptance is established by these Linux tests. Public model/fixture downloads run only in explicit CI setup; image inference itself is local CPU. Published build8 is untouched.
