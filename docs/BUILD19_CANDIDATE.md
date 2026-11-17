# Orivyn 0.1.3 (19): local integrated candidate, not published

## Exact base provenance

The GitHub connector read
`https://api.github.com/repos/R347H4CK3R/Orivyn/git/commits/c33cf144bbdd90965516054f41cc27d259c8592e`.
The published build18 commit's tree is
`e05df7f384d31af97032e949ad8d543e13796954`.
Local `git rev-parse f8e7f00^{tree}` returned that exact tree. Thus the complete
tracked local base is identical, not merely selected app files. The commit IDs
and parent lineage differ; do not advertise the local base commit as the
published remote source ID.

Local integration includes `7ab763b`, `ef81845`, `ecded2e`, and stream patches
originally `72b8351` and `8a987ea` (integrated as `8fdf9c7`, `269bc39`).
The app keeps bundle identity `app.jarvisevo.ios`, existing data formats and
signing/update requirements. No migration, destructive reset, or import rewrite
is included. No video downloader or unrelated unfinished work is included.

## Metadata

`project.yml` and bundled `Info.plist` agree on 0.1.3/build 19, with updated
`OrivynReleaseNotes` displayed by the existing Settings UI. The version guard
passed against the connected live Distribution source containing 0.1.2/build 18.
That is a preparation-time check; fetch fresh history again before publication.
`build19-catalog-draft.json` carries truthful candidate wording and is explicitly
NOT a source catalog. No release date, downloadable IPA, byte count, hash, native
pass, or publication is invented. Actual live catalogs remain unchanged.

## Native gate and current repair status

The first candidate was uploaded as remote commit
`416ef3b0ad7465f9a483c107db4f191758dfe4d5` (tree
`bf5781ac1a51da0f1cbdf1ec538938aa50b36b26`). Native run
43998054896 selected 238 tests and returned 235 passes, 3 failures. Packaging
was gated off. No build19 IPA or release was published. The failures exposed
normal-loop code refusals/placeholders and missing required calculator/memory
reads. The original evidence remains preserved, not replaced by later results.

The follow-up repair separates bounded tool decisions from ordinary answer
inference. Fresh code requests use ordinary chat roles, not tool-decision JSON.
Explicit supported read requests narrow the decision grammar; a successful
single read transitions to answer synthesis without an irrelevant repeat.
Unknown compound requests retain the bounded decision loop. Explicit single
get_app_info answers render the exact durably recorded metadata by strict status
groups with full prerequisites and omitted-item counts, rather than trusting a
small model to relabel availability. This does not add execution capabilities.

1. Pin and independently review the final source/tree before a fresh native run.
   This document itself authorizes no upload or publication.
2. Retain the existing Xcode26.1 / iPhone16Plus iOS26.1 Simulator architecture,
   pinned Qwen3-1.7B-Q4_K_M and b9049 runtime, and all runtime verification flags.
3. The exact selected inventory is now 245 tests, requiring 245 passes, zero
   failures and zero skips. Static enumeration checks the count; it is not native
   execution evidence. Do not reduce assertions/counts to accept missing tests.
4. Native actual-model probes retain fresh, refusal-polluted and long-history
   code generation; add the user's multi-refusal sequence and contextual Explain
   follow-up. Calculator and memory must produce matching durable reads/results.
5. Explicit app-info must make exactly one real-model-selected read and render
   the exact recorded statuses/details. A separate actual-tokenizer post-read
   stress retains the full result and an irreducibly large goal, asserting an
   actionable context rejection without replay. This rejection is not counted
   as a successful answer. Capture both evidence scopes distinctly.
6. Only after the complete fresh native gate passes, package Release iphoneos
   from that exact source. Verify identity, version0.1.3/build19, bundled notes,
   IPA bytes/hash and catalog version guard. Packaging is not device acceptance.
7. Re-fetch Distribution and OmniForge before authorized publication. Use real
   IPA/source/gate metadata, preserve older versions/unrelated apps, update both
   app-level descriptions and version notes, then verify the public outputs.

Physical iPhone installation/signing, private backup/media mapping, thermals,
voice, HDMI and generalized multi-model response quality remain unverified.

## Local verification scope

- Final Foundation:643 tests passed, zero failures after compound-clause tightening.
- Python: 299 tests passed, one existing skip.
- Earlier integrated JavaScript suite:154 passes, zero skips/failures.
- Linux production-engine runs use pinned b9049 and exact Qwen3-1.7B-Q4_K_M.
  Iterations v1-v5 preserve failed outputs. v5 passed eight mechanical cases but
  app-info semantic review failed; it is not accepted as full behavior proof.
  Fresh v8 compilation/runtime passed all eight cases and independent actual
  tokenizer oversized post-read rejection/no replay. Four Python code blocks
  passed AST syntax checks without execution; app-info retained exact statuses,
  full details and two omitted items. These are pinned-fixture results only.
- Fresh native iOS and physical-device verification remain outstanding.

Local results do not establish general multi-model quality or physical-device
acceptance. Do not claim publication until IPA and public catalog checks finish.
