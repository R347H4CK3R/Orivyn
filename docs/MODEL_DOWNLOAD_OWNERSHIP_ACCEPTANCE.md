# Manual download progress ownership

Reproduced three stale-callback failures in exact extracted production `downloadModel` and `cancelDownload`: late progress repopulated a completed download, an older callback overwrote a newer same-model download, and late progress repopulated cancelled/completed state.

Each manual download now owns a UUID. Main-actor progress callbacks and final cleanup require that exact identity. The task/owner stay alive until actual completion so cancellation does not admit another operation while the store remains busy. Cancellation requests, automatic preparation rules and model-selection policy are unchanged. The DEBUG display fixture has no queued progress callback and retains its own task until completion.

The host runner compiles unchanged extracted methods with an explicit controlled async model-store boundary; six checks pass after the three red failures. It does not execute full AppModel, URLSession downloads or SwiftUI/iPhone behavior. Independent source review found no concrete regression.

304 Foundation tests passed again after verifying all source/test hashes matched the existing compiled suite. The initial rerun lacked explicit sandbox cache paths and failed during manifest setup; the corrected invocation passed.135 Python,74 agent Node and39 VM Node tests pass. Both rerun logs remain. No native/release claim.

Private checkpoint a086311de6f3acf6cb27446b9f23b5281ac7620a exact AppModel source verified. No IPA, main-branch or catalog write.
