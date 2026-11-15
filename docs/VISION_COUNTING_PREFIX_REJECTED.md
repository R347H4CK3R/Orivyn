# Counting prefix rejected

Run43681967233/source4cec3d7 used a general category-selective counting instruction with unchanged pixels, no case IDs/answers. Frozen acceptance remains9/10, including incorrect5instead4 in case08. Expanded holdouts score22/24, including5/6 newly authored mixed-category cases, but normal image descriptions regress badly: legacy6/9 and real ABI suite4/8. Several responses contain only punctuation. The three cancellation cases still pass; the ABI suite fails its four ordinary shape/color output checks, not cancellation. Output exhaustion protection passes. Full failures are preserved in docs/evidence/vision-lfm-counting-regression-20261115.json, artifact14149046194.

The unprefixed LFM baseline built from sourcea03ca637 passes all9 legacy checks, all8 real ABI scenarios (four ordinary inferences, three cancellation phases, one blank guard), and the one-token output-limit check. Preserve that original bridge for app integration; do not cherry-pick this branch's prompt change. Its frozen result remains9/10, so mixed-shape counting must still be described as unreliable.

These are Linux CPU diagnostics, not iOS/device acceptance. Neither original acceptance criteria nor failure outputs were changed to make a candidate pass.
