# Model removal identity

A stale caller descriptor could delete the currently installed model file while removing all entries with that ID. Removal now requires exactly one current ID, full descriptor equality and an unshared filename before the existing file/manifest transaction. Unknown, stale or ambiguous selections stop without deleting live files; unrelated manifest order is preserved. Planning and transaction execute synchronously within the store actor, with no intervening await.

Six Foundation tests cover identity fields, missing/duplicate IDs, shared filenames and preservation. The host smoke executes the exact extracted production remove method plus actual ModelInstallTransaction on synthetic files, with a controlled descriptor-lookup boundary. RED reproduced current-file deletion by stale selection. GREEN verifies stale and unknown rejection plus valid transactional removal. The first green run lacked disk space during fixture setup; after removing recorded superseded synthetic test databases, the same compiled executable passed. This does not test full native LocalModelStore, actual weights or iPhone filesystem behavior.

310 Foundation tests,135 Python tests,74 agent Node and39 VM Node tests pass. Native LocalModelStore regression was added and parsed, not executed. Source review found no concrete identity/path regression. Native release gates remain outstanding.

Private checkpoint ee22c1f53a3866b62dd3c78d7d8bb8399a2a348f exact store source verified. No release or catalog change.
