# Independent validation — 2026-11-14 19:42 UTC

Current native branch inspected: codex/complete-capabilities-20261114.
Exact source independently tested: bd4b4944ccf29ccd3aa36f99e2d2393e6c932dd7.

## Failure reproduced and correction independently verified
Run 43633247253 at 194f30a failed the Python conversation-management contract before native testing. Its core job log (132564336077) reported the same missing substring reproduced locally: the test still expected store.save(proposed) after production moved to saveConversation(proposed).
Prepared and locally tested the equivalent correction, then observed upstream bd4b494 had already committed it. Preserved that commit instead of overwriting the active branch or duplicating the repair. Tested the exact upstream commit after discarding only our redundant local test edit.
The corrected contract retains save-before-visible-mutation ordering and verifies the helper awaits the store before transferring attachment ownership. This is structural evidence, not an XCTest pass.

## Fresh checks on bd4b494
- Pinned guest fixture materialization succeeded.
- Python: 187 executed, 186 passed, one existing real-tokenizer test skipped.
- JavaScript agent: 104 passed, zero failures/skips.
- JavaScript VM: 39 passed, zero failures/skips.
- Model catalog check: exit 0.
- No Swift compiler or Apple runtime testing performed locally.

## Native evidence and pending repairs
Run 43627151441 at 4ce8001 completed with failure. Retrieved its actual job log (132545510565): 923 unit tests executed, one skipped, six failures, involving attachment cleanup and generated-image rollback. UI failures included real automatic inference, saved local-task flow, selected text export and verified local reads. Some other suites passed; the overall native gate did not.
The newer commits include owned-import rollback changes and UI/test changes. Their native behavior is still pending; do not mark the repairs or inference accepted from source inspection.
At this check run 43633448757 on bd4b494 was queued. Run 43633247253 still had an inference job active although its four core/UI jobs had failed the stale Python contract. No jobs were cancelled or dispatched by this validation session.

## Release boundary
Latest public release listing still shows Orivyn 0.1.1 build 6, published 2026-11-14 17:19:48 UTC:
https://github.com/R347H4CK3R/Orivyn-Distribution/releases/tag/orivyn-v0.1.1-build6
Asset: Orivyn-0.1.1-build6-unsigned.ipa, 35,042,297 bytes.
Published digest: 86adf180469d44b927cfc078adb5fcf315c5a4da9a1078f613788771640db79e.
Package bytes were independently verified in an earlier checkpoint, not redownloaded here. No new release, device installation, voice acceptance, visual comparison, or completed 1.0.0 claim.
Next: assess the new exact-source native and real-inference results before any publication. Work between checks is not assumed to be continuous.
