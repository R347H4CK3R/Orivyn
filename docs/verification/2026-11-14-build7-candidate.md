# Independent native/package checkpoint — 2026-11-14 20:43 UTC

App branch observed: bcf0e0e0dffdb2178487376b8a6b434d631e226d.
CI package source: 67d9aa960d07ff1fe0961708d99228dc778b75d4.
These revisions are distinct; do not transfer exact-source test claims.

## Native core and artifact
Fetched actual job 132575186858 logs from run 43636771104.
953 XCTest cases executed, three skipped, zero failures; native core job succeeded. Release iPhoneOS build and package checks succeeded.
Downloaded artifact 14131107571 (Orivyn-native-capability-evidence-core), extracted its actual IPA, and independently ran scripts/verify_ipa.py against the downloaded bytes: exit 0.
Orivyn-0.1.1-build7-unsigned.ipa: 36,973,869 bytes.
SHA256 6b9f7d2d94f00b05a963ec332b5641369891035aa65e63cb44766071cb488b07 matches CI's package result.
ARM64, minimum iOS26.0, bundle app.jarvisevo.ios, version0.1.1 build7. Bundled runtime/resources/notices and fixture-exclusion checks passed. Machine-readable result accompanies this report.
This is a development CI candidate, not a release or device installation result.
Run: https://github.com/R347H4CK3R/Orivyn/actions/runs/43636771104

## Failure diagnosis
Retrieved job 132571784638 from run43635664229 at bc141cc: production native tool test failed with nativeGenerationFailed(status:3, elapsedSeconds:60.80819225).
Confirmed bridge.h defines status3 as OV3_EXPIRED; LlamaEngine creates the native session with TTL60000ms; bridge checks expiry cooperatively around decoding. This identifies the failure condition, not a demonstrated performance repair. No TTL, model policy or acceptance check was weakened.
The same inference log reports a successful vision test before the tool failure. A separate stored vision receipt describes a red square smoke input; neither proves broad image understanding or device performance.
Prior UI job132571784612 failed locating verified.report. Newer source adjusts the flow; current native UI/inference results remained pending at inspection.
Latest queued run43637615360 tests bcf0e0e with a cold-WebKit readiness adjustment.

## Fresh portable verification at bcf0e0e
187 Python tests: 186 passed, one real-tokenizer skip.
108 JavaScript agent tests passed, zero failures/skips.
Model catalog check passed.
No local Swift/compiler/device test claimed.
Reviewed durable-text-outbox documentation: implementation is dormant sender-side SQLite persistence, with no live sync transport, pairing or automatic transmission enabled.

## Release and next work
Public release listing remains 0.1.1 build6, published 2026-11-14 17:19:48 UTC. No publication performed here.
Physical iPhone/SideStore, voice/audio, visual parity and full 1.0.0 acceptance remain unverified. Next: finish exact-source UI and inference checks, profile the bounded tool timeout, and publish only within verified evidence. No continuous execution between checks is assumed.
