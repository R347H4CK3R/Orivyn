# Isolated LFM vision app integration

This branch selects the tested, unprefixed official LFM2.5-VL1.6B Q6_K/f16 pair for the existing image-analysis provider. It does not change the selected text/chat provider, execute tools, or send image pixels to a remote service. The C bridge and original pixel coordinates are unchanged. Main and published build9 are separate; integration requires the targeted app result and the parent's final combined-source checks.

## User flow and data preservation

Download or verify vision model remains an explicit user action, using pinned HTTPS Hugging Face model URLs and exact bounded SHA256/size verification. Analyze image never downloads missing weights. Imported images continue through the owned-file/ImageIO/RGB boundary and local native inference. Existing Smol files and Apache notice are retained; users of that prior pair must explicitly install the new pair to use this candidate. No user attachment, conversation, or old model file is deleted. The pair lease/install exclusion and cancellation paths are unchanged.

The screen shows the model name,1.82GB download, full LFM Open License1.0 text and source attribution before setup, plus a specific warning that counts and shape distinctions can be wrong. If the bundled license is unavailable, setup is disabled. The official license has commercial-use restrictions and redistribution obligations; it is not Apache2.0. Its exact bytes are retained as JarvisEVO/Resources/LFM-Vision-LICENSE.txt, SHA25661d7e939a05911c765b7e98ffaa1ab5ca6c0174a65350766c25cb10197d19fc8. This source integration is not a determination that every commercial deployment is licensed.

## Verified portable evidence

Run43681174499/sourcea03ca637: unchanged frozen10-case diagnostic9/10 versus Smol8/10. The reversed horizontal case is corrected, but four circles plus a square still produces5. Expanded strict holdout15/18 versus baseline12/18; all shifted relative positions and absolute halves pass. Two landscape outputs say valley, which the narrow predeclared answer set rejects despite plausible semantics. These strict scores do not establish general image accuracy.

Run43681967233 rebuilt the original bridge from a03ca637 and verified9/9 legacy checks,8/8 real ABI cases (four normal inferences, three cancellation phases, one blank guard), and one-token output-limit rejection with empty text and zero tracked handles. A generic counting prefix regressed ordinary descriptions and is rejected; it is not present here. Evidence is preserved in docs/evidence/vision-lfm-original-regressions-20261115.json. Tracked handle counts are not heap-leak or memory-budget proofs.

## App and release gates

Targeted Apple run43682659679 tests sourcef8663e9 with the real production PNG/ImageIO/store/native-runtime path, exact bundled-license assertion and acknowledged cleanup. Its outcome is pending at the time this document is created; no app-runtime pass is claimed yet. This is one required simulator smoke, not physical-device or broad-vision validation.

The release package validator requires the exact LFM notice in CFBundleVersion major10 or later and preserves historical1–9 package reverification.32 actual ZIP regression tests pass in run43682924391/source4e15aa0;12 focused in-memory resource cases also pass. This proves the validator's checks, not that a future Release IPA has passed them. The final parent build must use major10 or later and verify its real IPA.

Physical-device offline operation, memory/jetsam, thermal behavior, latency, wider image/OCR quality, live UI download/cancellation and final combined-source Release verification remain separate gates. No general autonomous vision/tool behavior or1.0completion is claimed.
