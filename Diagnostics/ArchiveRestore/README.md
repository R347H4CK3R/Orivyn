# Native synthetic ZIP restore gate (not executed locally)

This gate builds the actual Orivyn app and a separate simulator-only Files document
provider named **Archive Fixture**. It selects the generated ZIP through the real
Files picker; no selected URL, prepared review or database result is injected.

The ZIP is generated exclusively from fixed synthetic strings and identifiers by
`make_fixture.py`. It contains one two-message conversation, one unresolved media
pointer, a corresponding unsupported binary file and an extra retained record.
It contains no user archive, credentials, account input or external downloads.
The unsupported media is intentionally **not** claimed to be a working attachment.

Three UI scenarios are required:
1. Real ZIP picker cancellation/reopening does not import history.
2. Selection → review with real counts → explicit commit → relaunch → one restored
   conversation with both original message texts visible and composer available.
3. Preparation survives relaunch without activating history; retained review must
   be selected and explicitly committed before its conversation appears.

The simulator gate requires exactly **73 passed, zero failed, zero skipped**:
50 core/preservation/association/SQLite tests, 15 conversation/tool component tests, five AppModel routing/persistence tests and three UI tests. A separate
`swift test` invocation runs the ArchiveExtraction package on macOS and is not
added to the simulator result count. All package tests must pass.

## Prerequisites and trigger

`.github/workflows/archive-restore.yml` is restricted to a public repository and a
standard GitHub-hosted `macos-15` runner. It requires Xcode 26.1 at its exact installed
path, the iOS 26.1 iPhone 16 Plus simulator selected by the existing selector,
xcodegen, and the existing pinned combined runtime/model fixture build flow.
Existing cache keys are reused; cache misses build the reviewed runtime. No larger
runner, purchase, secret, signing identity or production release is configured.

The workflow runs only after a push to `recovery/chatgpt-restore-20261116` that
changes `.github/workflows/archive-restore.yml`. Source edits alone do not
redispatch this bounded acceptance run. A later intentional rerun must modify the
workflow or use GitHub's rerun action; never infer a current pass from an older SHA.
No trigger or push has been performed by the fixture author.

Artifacts retain the exact source commit, scope, boot inventory, native build log,
xcresult summary and screenshots for seven days. There is no IPA publication,
release creation, catalog update or private input access in the workflow.

## Local checks and limits

Linux validation can check generated ZIP integrity/schema, test-selection counts,
plist/YAML, shell syntax and Swift parsing. It cannot typecheck Apple UI APIs or
prove Files accessibility names, native concurrency behavior or successful UI
interaction. Actual runner execution is still required. Simulator success would
not establish physical-device or the user's multi-gigabyte archive acceptance.

Synthetic temporary roots in selected native tests resolve `/var` symlinks before
calling components whose documented contract requires canonical paths. This
changes test setup only, not production path checks.
