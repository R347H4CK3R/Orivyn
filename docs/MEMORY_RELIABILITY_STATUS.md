# Saved-memory reliability candidate

Source changes, native tests not run.

Saved memories now support literal case/diacritic-insensitive all-term matching. Search never calls a model/network, preserves original ordering and identifiers, rejects oversized query input and treats regex-looking input literally.

The prior editor initiated an asynchronous save and immediately dismissed, so a persistence failure could lose the user's editing context. It now waits for a real success result, keeps text/error visible on failure, disables edits/dismissal while saving, and gives each new editor a stable memory UUID so retries cannot create duplicate notes. The model also enforces the4000-character bound independently of UI controls.

Authored native tests cover literal search and an actual SQLite failure trigger followed by same-ID retries. They have not run. Portable structural checks verify the intended await/success-only-dismiss and bound paths, not runtime behavior. Actual UI saving/failure/locking and native tests remain required. No published app/version changed.

Source review found no definite Swift/API mismatch. The store byte limit is now also enforced and displayed (32768UTF8bytes), with an authored combining-mark overflow regression. Native tests remain unrun.
