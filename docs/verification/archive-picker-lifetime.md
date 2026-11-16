# Archive picker lifecycle candidate

## Observed native failure
Run 43816635355 at source 7d05712: 73/75 tests passed, two failed, none skipped. The cancellation/reopen test failed at the **first** picker presentation (line 92), not during cancellation. The two actual ZIP selection/review/commit/relaunch tests passed. The failure log shows Choose ZIP tapped at 16.41s and missing Files navigation at 27.33s. Screen recording frame 18s shows a sheet beginning to cover the restore page; the failure hierarchy has only the restore page.

## Hypothesis and bounded change
The host's unconditional onDisappear reset of `choosing` can tear down its own covering document picker. The artifact does not record lifecycle callbacks, so this explanation is probable, not proven. This candidate preserves the lifetime only during an owned picker presentation, hides parent Back/disables interactive dismissal then, and adds lifecycle progress events. Real hierarchy removal independently revokes a non-observable captured token through UIViewRepresentable dismantling. Background revokes the token and closes presentation; a later active appearance creates a fresh token. Existing active/nonce checks remain. Preparation cancels on genuine departure/background; durable commit is not cancelled.

## Verification
- Existing three native UI acceptance tests are unchanged, including two cancel/reopen attempts and no-import assertions.
- Swift frontend syntax parse passed. This is **not** Apple SDK typechecking.
- 533 Foundation tests passed on Linux, including two captured-token revocation tests. The existing unsupported corelibs URLProtocol redirect test remains excluded on Linux and required on Apple.
- UIKit dismantle/cover semantics and the actual picker fix are **unverified** until a native rerun. No CI was triggered and nothing was published by this worker.
- No private archive or user data was accessed. Inspection used synthetic CI artifacts.
