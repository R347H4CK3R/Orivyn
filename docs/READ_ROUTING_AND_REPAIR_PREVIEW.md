# Scoped request routing and repair-preview safeguards

## Request routing

The English whole-request router supports only app identity/capabilities, installed-model names, and local conversation search with a quoted exact query. It handles conjunctions outside quotes and requires every clause to match. Negation, ambiguous pronouns, conflicting searches, unquoted queries and unsupported appended actions produce no partial plan. Quoted query content remains inert search data.

The native UI only proposes visible toggles/query. The user reviews, creates and runs a separate deterministic plan. It does not execute when parsing, does not use a language model, and is not unrestricted natural-language autonomy. Eleven actual-code routing tests pass. Native route/UI tests are authored, not run.

## Source change preview

An explicitly selected source file from the authenticated inspector can be edited in a local temporary draft. The native bridge rechecks original Git blob SHA-1 framing/hash before accepting it. The pure formatter validates exact fields, bounded UTF-8, safe relative source paths and base identities, then generates a bounded linear-time single-hunk unified diff with newline markers.

No repository write, branch/commit, model inference, code execution, compilation, IPA creation or installed-app replacement occurs. The diff is visibly labeled draft-not-applied/not-tested. The user manually edits the proposed replacement; this is review infrastructure, not autonomous self-repair. Changes invalidate the old diff. The draft is not saved or transmitted automatically.

Ten actual-code formatter tests pass, including applying generated diffs with system `patch --fuzz=0` in temporary test directories and comparing exact bytes for empty files, CRLF, missing final newline, Unicode and long lines. Malicious paths, schema extras, invalid encoding, unchanged source and over-budget output reject. Native hash/UI tests remain uncompiled/unrun. Private source stays private; no token was used in these tests.

General model autonomy remains failed on both tested small models. Native compilation, simulator/iPhone testing and real authenticated inspection remain release gates. No paid CI or publication occurred.

Source review caught an unstable child-navigation origin when the inspection screen clears its selected file. Draft presentation now uses a stable sheet selection outside that conditional source view, and background/disconnect clears it. Native presentation/dismissal behavior remains unverified. Protected .git paths reject case-insensitively. Final portable gates:94 Python,60 agent/router/draft JavaScript,39 VM JavaScript tests pass.


## Reviewed patch export — 2026-11-14

The source preview now offers **Export reviewed patch** through the system Files exporter. It captures one immutable UTF-8 patch, with a flat bounded suggested filename, original commit/blob IDs, path, summary and an explicit not-applied/not-tested label. The exported diff is byte-identical to the displayed diff. No token or other unselected source files are included. The user chooses the destination; a cloud Files provider can sync the private source snippets. Nothing is saved automatically.

Edits invalidate export eligibility by exact UTF-8 comparison of both replacement and summary, including canonically equivalent Unicode and line-ending changes. A failed/canceled export leaves the reviewed draft available. Success is reported only from the file-export callback, never merely from pressing the button.

Six new JavaScript tests pass alongside the ten existing formatter cases. They invoke actual `git apply --check` and `git apply` against isolated fixtures, including real Git base identities, empty files, Unicode, CRLF, missing final newlines, changed-hunk rejection and inert command-like summary text. Four exact-production Swift review-binding tests also pass on Linux. Full portable aggregate: 400 Foundation tests, 104 agent JavaScript tests, 39 VM JavaScript tests, and 159 Python tests (one existing tokenizer skip); catalog check passes.

Patch-header identities are provenance, not automatic freshness enforcement. Before an external apply, verify the target commit and original blob, inspect the diff, and test the resulting change. Changes outside a patch hunk may not make `git apply --check` fail. Export is not self-applied repair, GitHub publication, compilation or an IPA update.

The native Swift bridge/exporter changes passed syntax parsing only. Apple SDK type checking, Files destination/name/cancel behavior, scene dismissal and device verification remain unrun at this checkpoint. Existing parent-screen credential/source clearing behavior is preserved. The user subsequently authorized a free Mac runner for packaging; no native success is inferred from that authorization.
