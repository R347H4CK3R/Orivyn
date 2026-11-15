# Remaining capability implementation plan

> For agentic workers: execute the independent vision, sync and autonomy work in isolated source copies, then review and verify together before backing up the private branch.

Goal: implement the missing runtime and persistence pieces for the owner's requested local autonomy, visual understanding and device synchronization without weakening acceptance or publishing another preview.

Architecture: retain the one-model heavy-work lease; extend real pinned native inference rather than emulating model decisions; commit received text and replay receipts in one SQLite transaction. Keep unverified native transport/model selection disabled. Existing designs in Diagnostics/VisionRuntime/NATIVE-MTMD-DESIGN.md and the peer-security design guide integration; prior research is not native acceptance.

Tech stack: Swift 6, SQLite, C++ llama.cpp b9049, its common Jinja/PEG parser and mtmd; Python/Node host verification.

Constraints: source remains private, no paid service, no new preview publication, no silent model-size increase, no arbitrary unauthenticated peer connection. Optional Mac verification is skipped per owner; eventual full native and physical tests remain release blockers.

- [x] Autonomy: implement real borrowed-context template/grammar/sampler/parser generation. Evaluate a checksum-pinned model below the existing 2,000,000,000-byte file cap. Reject partial output, replay, invalid calls and canceled work. Preserve actual tool-quality failures.
- [x] Vision: connect lifecycle ownership to the existing heavy-work lease, retain ownership until teardown, add real native load cancellation and run the actual vision bridge against fixed synthetic images. Report wrong answers; do not substitute OCR.
- [x] Sync: make bounded reviewed text import and receipt persistence atomic. Bind replays to exact payload, pair generation and installation epoch; keep conflicting edits, reject stale scope and prevent deleted data resurrection after reset. This is a storage prerequisite, not an authenticated transport claim.
- [ ] Integration: review worker diffs, reject overlapping/out-of-scope changes, materialize the pinned VM image in the clean checkout, run portable aggregate and each real component gate. Record exact source hashes and native exclusions. Commit validated source to codex/complete-capabilities-20261114.

Review focus: cancellation after inference but before cleanup; model/context ownership mismatch; malformed or adversarial tool output; ambiguous SQLite commit/retry; repeated batch after deletion or device restore. Each worker must exercise its relevant conditions.

Completion requires actual app wiring and accepted end-to-end outcomes, not merely these components. If current model quality or missing Apple identity/runtime prevents safe activation, retain the useful private code and report the precise blocker without calling 1.0.0 complete.
