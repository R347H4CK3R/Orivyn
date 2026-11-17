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

## Native gate plan (not run or dispatched)

1. Review the final combined source and pin its commit/tree; keep the checkout
   clean. No branch upload, action dispatch or publication is authorized by this
   document. Keep uploaded evidence synthetic only.
2. Use the existing public synthetic gate architecture, Xcode26.1, iPhone16Plus /
   iOS26.1 Simulator, pinned Qwen3-1.7B-Q4_K_M fixture, and combined-runtime
   verification. Preserve the three existing native feature flags and verify
   their runtime archive before both test and Release builds.
3. `scripts/ci_archive_restore.sh` now requires exactly 238 selected tests:
   NormalChatLocalAgentTests 20→29 (+9); ChatResponsePolicyTests 12→25 (+13)
   over the published 216 gate. The static composition test enumerates each
   selected XCTest class/method, including multiple classes in one file, and
   confirms 238 distinct selections with zero failures/skips required.
   ProductionNormalChatLocalAgentTests still has 2 methods; the added probes
   are inside its existing actual-model method. Recalculate if selected methods
   change; never lower the count to accept missing tests. This is gate wiring,
   not an assertion that 238 native tests have run.
4. Retain all existing restoration/privacy/review-invalidation tests. Actual
   model coverage must exercise fresh generic Python drafting and a refusal-
   polluted history through normal-loop AND direct paths, as now present in
   ProductionNormalChatLocalAgentTests. Capture outputs/receipts, not only counts.
5. The selected actual-model method now includes six synthetic near-cap history
   excerpts before the generic Python probe, and a separate actual get_app_info
   call followed by real engine continuation. It asserts exactly one read, one
   durable success receipt, two model requests, exact retained goal/result, and
   either a nonempty filtered answer or ONLY the explicit context-limit error.
   The latter is a documented limitation, not successful semantic answering.
   Evidence attachment `normal-chat-real-tokenizer-post-app-info` records the
   outcome. This native probe is added but uncompiled/unrun locally; it MUST run
   without skips before publishing. Long-history Python response content is an
   assertion to test, not a promised result. No native test method count changes.
6. Only after the exact native gate passes, run the separate Release iphoneos
   compile/package via `scripts/ci_package_only.sh` on the same source. Verify
   IPA identity, 0.1.3/build 19, bundled notes, artifact bytes/SHA256 and version
   guard. Packaging alone is not model or device acceptance.
7. Before any authorized publication: fetch fresh Distribution and OmniForge
   state; ensure both version and build exceed all published versions. Prepare
   full validated catalog entries using the real IPA metadata, source commit,
   actual gate URL/scope, publication time and hash. Update app-level description
   and version notes, preserving older versions and unrelated apps. Regenerate
   unified source, verified fallback and storefront together; independently
   fetch all live outputs afterward. No release claim before those checks.

Physical iPhone installation/signing, private backup/media mapping, thermals,
voice, HDMI and generalized multi-model response quality remain unverified.

## Local integrated verification

- 636 Foundation Swift tests passed, zero failures.
- 299 Python tests passed, one existing skip (including two native-gate contracts).
- 154 local-agent JavaScript tests passed, zero skips/failures.
- Release version guard passed against the observed live catalog; source plist and
 project metadata match.
- `git diff --check` passed.

These checks did not compile the iOS application or run the real llama tokenizer,
GGUF inference, simulator, physical device, or publication workflow. The packaged
IPA does not exist for this candidate yet.
