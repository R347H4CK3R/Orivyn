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
