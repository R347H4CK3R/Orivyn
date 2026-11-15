# Combined peer app compiler failure and candidate workaround

The first combined flag-enabled application gate did not build. It did not reach simulator test execution.

- Source commit: `7231e0ef2123e28234da144677d96fa1b48e7ee3`
- Run: https://github.com/R347H4CK3R/Orivyn/actions/runs/43681169334
- Job: `132711908400`
- Artifact: `14148328899`, `combined-sync-app-7231e0ef2123e28234da144677d96fa1b48e7ee3.zip`
- ZIP bytes: 63,948
- ZIP SHA-256: `e9c98b8534a559101dca5b3fd8c9af5694163ed8758fce6345b9409f45738385`
- Runner: macOS 15.8.2, arm64, Xcode 26 toolchain; Swift 6.2.4.
- Build exit: 65. The failure was a compiler crash during IR generation, not an ordinary source type diagnostic.

The preserved artifact's `peer-app/build-iOS.log` identifies IR generation for `UI/PeerSyncSettingsView.swift` and the emitted SIL thunk:

```
@$sSbScA_pSgIeAghyg_SbIeAghn_TR
```

The thunk is consistent with Boolean actor-isolated getter reabstraction. That is a diagnosis hypothesis, not an independently minimized compiler reproducer. The candidate removes both hand-built Boolean Bindings in that file: conversation selection uses an explicit checkmark button, and sync enable/pause uses explicit action buttons. These controls still call the same permission-checked session methods. No actor isolation checks, compiler checks, or feature gates are disabled.

This change requires the next combined native compile and tests. It is not evidence that the compiler crash is resolved, that pairing UI executes correctly, or that physical-device networking works.
