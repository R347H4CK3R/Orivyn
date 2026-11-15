# Build 15: explicit local checklist candidate

Version 0.1.1 build 15 is an unfinished development candidate, not completed 1.0.0. No publication or exact-package success is implied by this document.

## Change and boundaries

A manually selected, explicitly reviewed checklist can require up to three distinct read-only operations: bundled app information, installed-model listing, or a bounded exact saved-memory search. Review binds the goal, selected local model and exact arguments. Approval saves a ready task; Run is separate. Successful results must be recorded in order before the model can answer. This is not general autonomous planning or proof that an answer is correct. Generic tasks and their existing behavior remain experimental. Existing version 1 and reviewed-conversation version 2 task records remain distinct; new checklists use version 3. No automatic migration or execution is added.

Preserves build 14 reviewed-conversation discoverability, build 13 conservative installation recovery, build 12 snapshot leases/recovery and build 11 backup replacement confirmation. No existing release asset or catalog entry is deleted.

## Evidence before release packaging

Isolated source 054536dd821f1fe60cfd4a3dc89c10c86ebdb0de passed [run 43771669167](https://github.com/R347H4CK3R/Orivyn/actions/runs/43771669167):
- One actual ARM64 iPhone 16 Plus/iOS 26.1 UI test exercised exact review, disabled composer, discard/edit, navigation invalidation and explicit approval without Run.
- One relaunch UI test preserved the same approved checklist; exported JSON was identical: ready, zero steps, empty history, no pending operation or answer.
- One separate default-stream Qwen3-1.7B-Q4 real-model test performed app-info then memory search in order, answered with an unpredictable memory-only marker and joined cleanup. One passed, zero failed or skipped in each phase. This model test uses programmatic review/approval, not the UI test's task.

Earlier native session gate ran 31 deterministic tests with zero failures/skips. Portable JavaScript contract regressions and Foundation policy tests are separate evidence. Earlier failed UI attempts and a Bash 3 harness failure are retained; no inference success is claimed for the run that exited before producing a test result. The gate now requires actual result-bundle metadata, exact summary, configured test/model and successful subprocess outcomes rather than trusting exit status alone.

The build 15 release-specific workflow reruns scoped UI and real-model acceptance on this integrated source, then separately compiles Release for an ARM64 device and validates the actual IPA/resources. Those candidate results must be inspected before publishing. Existing aggregate Python baseline failures remain disclosed; no full-suite pass is claimed.

## Unfinished

No physical iPhone/SideStore, voice/thermal/battery/HDMI acceptance is established by these tests. Generic autonomous requests may still answer prematurely. Vision remains experimental; live automatic synchronization and self-applied repair are unfinished. External model/provider capabilities and possible provider costs are not reproduced or made universally free. Models download separately and are not bundled in the IPA.
