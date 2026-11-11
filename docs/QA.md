# QA evidence and release gates

## Verified on Linux, 2026-11-11
- Initial eight package-verifier fixtures were observed failing before implementation, then passing after implementation. Five later regression fixtures for framework type/deployment and ZIP aliases/collisions were observed red then green. The full current Python suite has 17 passing tests, including model-integrity fixtures.
- Tests reject missing/empty executable, x86-only binary, simulator platform, old deployment target, traversal and a renamed non-app ZIP.
- Shell syntax checks are separate from executing a macOS build.

## Not yet run
- Swift compilation, native XCTest and UI tests.
- Real downloaded-model inference and offline fallback.
- Device ARM64 build and verification of the resulting real IPA.
- Voice, attachment, persistence and navigation on a simulator/device.
- iPhone 16 Plus performance, thermal, memory pressure and battery measurements.
- SideStore signing/install/refresh and LiveContainer compatibility.
- Visual comparison with owner-supplied reference screenshots. No reference media accompanied the retrieved brief.

## Current build blockers

The connected executor is Linux, without Swift or Xcode. The GitHub private-repository free allowance is exhausted. Codemagic's existing account is a possible free macOS route, but private repository access must be authorized first. Neither a planned workflow nor a pending permission counts as a successful build.

No IPA, release or catalog item may be labeled verified based solely on source files or fixture tests. Record exact commit, build URL, test names/counts/skips, runtime/model SHA, simulator/device, screenshots and package report for each candidate.
