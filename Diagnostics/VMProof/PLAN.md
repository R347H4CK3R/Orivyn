# Isolated native VM proof plan
Authorized throwaway technical prototype only. iOS 26 / Swift 6 / public WKWebView. No main-app edits, release, external computer runtime or CI launch.
1. Test JS ownership, bounded keyboard input, stop-during-asset-load and stale event rejection before implementation; actual pinned BIOS execution separately verifies real CPU execution.
2. Prepare immutable bundled assets with exact lengths/hashes. No guest ISO. Preserve emulator/firmware provenance and notices. Not distribution approval.
3. Dedicated nonpersistent WKWebView, one exact custom origin/path allowlist. CSP only bundled scripts, WASM evaluation and same-origin fetch; no frames/workers, remote URLs, navigations, downloads, new windows or native data bridge.
4. Message envelope: version 1, owner UUID, event enum ready/running/stopped/error and bounded instruction count. No guest payloads become commands.
5. Start/Stop owns the whole view. Background, memory/thermal pressure and WebContent termination invalidate ownership and remove web view. Never claim immediate WebContent process memory release.
6. Native XCTest policies and real UI BIOS/WASM smoke. Swift/WebKit cannot execute locally; preserve unrun status. Later guest acceptance needs actual GUI pixels, typing, file read, snapshot/relaunch.
No persisted snapshots/imports in this nonpersistent harness. No full desktop claim. Future reviewed persistent storage is required for app-relaunch state; no large base64 bridge.
