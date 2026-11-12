# Native capability gate, 12 November 2026

Private remote commit: 1d371e681dc995236cf174eaa25b57a15e54fb9a.
Codemagic run: 6af62ca910a05158d8122577. This was an isolated proof run, not a product release.

- Native pinned llama/mtmd framework compiled (FRAMEWORK_STATUS=0).
- Vision: 13 of 14 test cases passed. Actual image encode/decode/output, cancellation/release, worker overlap rejection and validation passed on the simulator.
- One image fixture test produced eight assertions: green component 38 rather than less than 10, one for each orientation. Orientation dimensions/asymmetric transformations passed. Investigate source color-space conversion; do not simply loosen tolerance or call production vision verified.
- BIOS harness failed its execution counter predicate after 40 seconds. Exported hierarchy shows `Loading local BIOS and WebAssembly…` and counter `0`, not a running guest. Background teardown passed. Need diagnose script loading/custom-scheme and message-origin boundary without relaxing isolation.
- No 1.0 IPA was generated or published. Existing catalog remains unchanged.
- These gates do not verify a graphical guest OS, physical iPhone performance, HDMI, or complete app integration.

The UI test now preserves a complete failure hierarchy and screenshot before asserting so subsequent failures retain the actual stage, not only the counter.
