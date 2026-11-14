# Capability implementation — 2026-11-14

This development branch extends the source after public 0.1.1 build 6. It is not
a new IPA or release, and does not complete the 1.0.0 acceptance checklist. The
published preview and its SideStore entries are unchanged by this work.

## Vision

A separate, checksum-pinned SmolVLM2 2.2B model/projector pair supplies actual
pixel inference. It is not OCR or text-only image description. The development image
analysis screen includes explicit model installation, a question, result and
cancellation. The production session owns the app heavy-work lease until native
teardown completes. Exact pair verification precedes use; installation cannot
replace a pair owned by inference. Uniform RGB images are rejected before model
loading, and token-limited output is rejected rather than presented as complete.

Vision requires the new combined native framework and ORIVYN_NATIVE_VISION.
The ordinary stock-runtime build explicitly reports that runtime unavailable.
Limited Linux image cases and lifecycle tests are development evidence, not a
claim of general visual reliability, Apple ImageIO correctness or phone memory
acceptance. See Diagnostics/VisionProof/Linux for inputs and actual outputs.

## Native tool suggestions

The native C driver generates structured proposals with the admitted Qwen3 model,
using its real template, grammar, sampler and parser. It borrows resources retained
by the engine owner. Proposals are bounded to two app metadata reads and cannot
execute an action. The production integration uses the existing reviewed-plan
flow; this does not establish general autonomous task execution or external-service
results. The combined framework is required for ORIVYN_NATIVE_TOOLS.

## Sync

SQLite atomically imports a reviewed text payload and its replay receipt. Exact
retries do not duplicate conflicting copies or overwrite later edits. Scope/payload
reuse is rejected; erase rotates the receive epoch and clears replay state. Tests
also cover missing metadata and cleanup on failed database initialization.

The separate native mutual-TLS control probe remains disabled. It has no content
transfer API and does not authorize a payload. Portable framing and storage tests
do not verify TLS. Identity provisioning, physical pairing, consent/session wiring,
causal revisions, attachment transactions, and real two-device behavior remain
unfinished. See PEER_TLS_PROBE.md and TEXT_RECEIVE_TRANSACTIONS.md.

## Packaging and acceptance

Diagnostics/CombinedRuntime provides a pinned recipe for one combined llama
framework exporting both tool and vision bridges. Linux linkage rejects unresolved
symbols and a second runtime dependency. Opt-in Apple bootstrap requires the zip
SHA-256 and checks headers, exported APIs, Mach-O platform and deployment target
before replacing the existing dependency. The package script records requested
native flags. A recipe and parser tests are not an executed Apple build.

The owner made the repository public and authorized standard free GitHub Mac
runners. Run [43624962284](https://github.com/R347H4CK3R/Orivyn/actions/runs/43624962284)
built and admitted the combined Apple framework, then compiled and linked the
simulator app on Xcode 26.3. The test target failed because DEBUG was omitted
from the native-enabled Debug configuration. That configuration is corrected in
4ce8001df8dd3bd0671c7969fc3fa462046b9ed1; rerun results remain pending.
No complete simulator pass, device IPA, physical iPhone test or new publication
is claimed. The app minimum remains iOS 26. No paid capacity or new account was
used. Full native and physical resource acceptance remain required.

## Integrated verification

The [final evidence record](evidence/capabilities-final-20261114/RESULT.json)
contains the combined-source results: 170 Python passes (one explicit skip),
400 Foundation tests, 104 agent tests, 39 VM tests, and 64 persistence/framing
tests. The combined library passed nine vision cases, actual production vision
inference/cleanup with documented Linux boundary substitutions, token-limit
rejection, five native engine lifecycle checks and two admission/revocation
checks. Logs and exact source hashes accompany the record. Foundation excludes
the unsupported Linux URLProtocol redirect fixture; Apple verification remains
unrun. The aggregate's optional amalgamation persistence stage is marked skipped;
the separate recorded host-SQLite run supplies the 64-case evidence.
