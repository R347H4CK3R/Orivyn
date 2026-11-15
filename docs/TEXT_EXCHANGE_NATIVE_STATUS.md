# Native text exchange verification — 2026-11-15

Isolated commit **070611282d74a0a3566174aefb907a4deee28b14** passed [run 43666103660](https://github.com/R347H4CK3R/Orivyn/actions/runs/43666103660) on a standard GitHub Mac runner. The evidence artifact was downloaded and its source manifest compared with the implementation bytes. PeerTextRevisionExchange.swift SHA-256: e9fe3fd4b5545fb3a84030f0c513185be3b465d39f8f9397e71ae4862f461b66.

- 7/7 actual authenticated Network.framework + SQLite exchange cases passed.
- 8/8 certificate/pairing authentication checks passed.
- 7/7 bounded channel checks passed.

A valid scoped request produced one matching receiver conversation and confirmed sender delivery. Unapproved IDs, wrong receiver epoch, receiver revocation and forged request digest left the receiver unchanged and sender unconfirmed. Forged receipt digest or transfer identity could not acknowledge the sender.

The corrected test-only run at 159b121 failed specifically because PeerTextRevisionExchange was absent. The earlier 91b471 test attempt failed before these assertions because the harness redundantly defined SDK SQLite3; that setup defect was removed.

This is a disabled one-shot transport/storage adapter on branch `codex/live-text-exchange-20261115`, not live automatic sync in the shipping app. Pairing identity provisioning/UI, lifecycle consent, unsaved-edit coordination, automatic scheduling, network/device acceptance remain incomplete. Commit 699764b adds a pending lost-receipt/retry regression: the receiver commits, connection is lost before acknowledgement, and retry must produce one import and a valid delivery receipt.

## Parallel verification

- Current 8ab97c4 native core and ui-1 jobs passed. The bounded agent-create scroll test now passed in ui-2; ui-2 still failed the separate Photos cancellation → Files picker test at line 26. No claim of a fully passing UI suite.
- New-conversation diagnostic branch `codex/navigation-repeat-20261115` adds debug-only lifecycle logs and three independent repetitions of the real-model test. Its first attempt aborted before app tests during Xcode-version detection. Commit d388dd4 removes an early-closing head pipe from the generated build recipe and its generator; a controlled delayed producer reproduces failure in the old pipeline and passes with full-output capture. The exact native abort cause is not established because the old recipe suppressed stderr. Native rerun pending.
- Tool-result encoding diagnostic branch `codex/agent-result-encoding-20261115` is running paired unchanged/decoded synthetic prompts on a fresh pinned Linux CLI. This does not change production prompting or acceptance gates.
- Alternative Qwen3-VL model experiment at ef6989c completed all ten unchanged frozen vision cases but matched only **4/10**. Spatial direction cases passed; counting and text cases regressed. It is rejected as a replacement. Current production vision remains SmolVLM2 with its previously recorded 8/10 synthetic baseline; no broad-vision completion claim.

Build 8 remains an unpublished draft. No SideStore feed changes.
