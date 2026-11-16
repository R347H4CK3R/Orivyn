# Portable Python contract refresh

Baseline: b7c67fa. Test-only maintenance; no app, native gate, or release changes.

The clean isolated checkout reproduced 271 Python tests with 4 failures, 4 errors,
and 1 existing skip. Investigation found stale harness contracts rather than a
runtime regression:

- Attachment fitting expected obsolete whitespace and a local variable. The
  replacement structural guard follows prepared entries through the model's
  formatter and vocabulary token counter, then final prompt/output token budget.
- Import disclosure expected a removed confirmation dialog. The current dedicated
  import page still requires pending replacement review, a destructive confirm
  action, cancellation, and an older-backup warning.
- Files cancellation expected the former policy-dialog tap. Its updated source
  guard retains real Files navigation, tabs, search and cancellation assertions,
  plus unchanged conversation-list and draft checks.
- The mocked native pipeline omitted generate_project.py and failed before its
  five independent gates. Adding that setup stub preserves every gate outcome.
- The clean checkout omits generated maintained.img. The test now invokes the
  actual pinned materializer into temporary storage, verifying compressed and
  expanded hashes and sizes, then the native allowlist. An existing bundled disk
  is still checked rather than replaced or ignored.

Verification: `python3 -m unittest discover -s scripts/tests` ran 271 tests with
zero failures or errors and the same one skip. The skipped self-knowledge budget
check needs the real tokenizer/catalog weights; no estimate was substituted.
`git diff --check` passed.

Five in-memory source mutations were independently rejected: measuring the wrong
prepared entries, omitting reserved output tokens, removing the destructive
replacement action, bypassing confirmation.confirm(), and replacing real Files
navigation with an unrelated page. No production files were mutated on disk.

These source guards and mocked pipeline checks do not establish native tokenizer,
Files lifecycle, device behavior, or release readiness. No CI was dispatched.
