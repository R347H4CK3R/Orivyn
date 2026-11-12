# Orivyn build 4 reconstruction verification

This evidence belongs to the newly reconstructed source, not lost local commit 079b849 or its catalog successor. Native results must identify their exact source commit.

## Local source checks, 2026-11-12

- 62 Python tests: PASS, including catalog evidence cross-checking/string escaping/freshness and historical/new branding package gates.
- `python3 scripts/model_catalog.py --check`: PASS.
- Shell syntax (`ci_macos.sh`, `run_native_tests.sh`, `bootstrap_llama.sh`): PASS.
- `git diff --check`: PASS.
- Build 4 and Orivyn display name confirmed; original bundle ID, scheme, storage and Keychain identities preserved.
- Nine exact pinned model metadata/template checks pass; see `model-catalog/`. These are not full-file inference or physical iPhone benchmarks.
- Independent source review covered workspace/preferences/runtime ownership and catalog/provenance. It found and repaired native-test reachability assumptions caused by the expanded sidebar/catalog. Native compile and touch behavior remain separate gates.

## Native gate

The final native gate passed on the exact source identified below. The reconstruction workspace lacks Xcode, so execution took place in the existing authorized Codemagic connection, not on this Linux machine.

The previously successful build 3, on CI commit `fa3c7bc65eaf363835f8f30f2243154971058802`, verifies only the recovered baseline. Its unsigned IPA was 2,945,869 bytes, SHA-256 `2d1541c319e26397e8032ee565e57bac03ae49a05cd1b8cfaef1896af7842b7f`. It does not verify this reconstruction. No release, signing, physical installation or actual iPhone performance is claimed here.

## First native pass and repairs

Codemagic run `6af5cd119679c85ac0af1c6b` on source `110499c31efa4e1dbc2aec222592d9b45b45c2d2` compiled successfully and passed all 288 native test methods, including actual Qwen inference and attachment analysis. Its UI run exposed two issues and is not a release gate pass:

1. The installed-model test required a decorative Image inside the Installed label to be tappable. The verified installed marker already existed. The test now reveals the actual model-name row instead, retaining installation, provider selection, real inference and relaunch assertions.
2. The new plain-style workspace route buttons did not give the transparent Spacer area a rectangular hit target. Center taps left the drawer open; the four workspace navigation tests failed. The route label now has an explicit full-row content shape, matching the working Settings row. These tests remain the regression gate.

The follow-up also adds named actual workspace/Behavior/project screenshots, raising authored UI methods to 27 without changing production behavior. The second native run below verified both repairs and produced the captures.

## Passing reconstructed build

- [Codemagic run 13](https://codemagic.io/app/6af4edea52f6da2271c62b79/build/6af5d1519679c85ac0af1e71): **success**, 2026-11-12 14:46:41–15:03:35 UTC.
- Exact tested remote source: `791dc4755a0ab1039d3fd628a9480d1d4419d182`, branch `recovery/orivyn-reconstructed-build4`. Exact tree: `776ab4b9bbe6aa228f11b68f5a72de7db6a85bb4`. Documentation-only follow-up commits do not change this tested-source identity.
- Xcode 26.0.1 (17A400), Mac mini M2, iPhone 16 Plus simulator, iOS 26.0.
- 62 Python tests, 288 native tests, 27 UI tests: **all passed, zero failures and zero test skips**. Per-case native/UI logs reconcile to 315 passing methods.
- Actual pinned Qwen download, integrity verification, selection, real local response and conversation/model persistence after relaunch passed. The captured answer is “The capital of France is Paris.”
- All five reconstructed workspace UI methods passed, including full-row navigation, unchanged drafts across routes, Projects persistence, real default Behavior editor, and independent Space/Images filters. The active-download cancellation/filter regression also passed.
- Release ARM64 device build and package verification passed. A separately downloaded IPA was verified again locally; its complete report exactly matches CI.
- Billing remains disabled, with no transaction history. After this run, 263 of 500 free macOS minutes were used, leaving 237 at the observed time. No recurring charge was enabled.

### Exact package

`Orivyn-0.1.0-build4-unsigned.ipa` is 4,192,549 bytes; SHA-256:

```
2e6084156b59d7cb0451a0bffc28cd3542264cca8416c4f508bb39ea2154be2c
```

Version 0.1.0, build 4, ARM64 iPhoneOS, iOS 26.0 minimum, unchanged bundle ID `app.jarvisevo.ios`. The pinned llama framework is present. Required KaTeX script/license digests match. DEBUG fixture markers, test-only photo media and GGUF model weights are absent from the shipping package. The first model download remains separate from the small IPA.

### Visual inspection and evidence

Actual native simulator captures, not mockups, cover light/dark chat, the sidebar, the installed model catalog, real local conversation, all reconstructed workspace routes, Projects creation/relaunch and the default Behavior editor. The catalog's installed badge and complete default-model guidance are visible without top clipping. The single-row composer and dark/light toolbar controls are legible in the inspected captures. These observations are not a claim of pixel-perfect reference parity or a complete accessibility/device-size audit. The reviewed workspace captures are light-mode iPhone 16 Plus, mostly empty/default states. Lower Behavior/Customize content requires scrolling; the Plugins Location row is only partly visible at the native search-area boundary in its initial scroll position. Lower sections, populated galleries and other device sizes remain outside this screenshot inspection.

The companion `Orivyn-build4-verified-evidence.zip` preserves native/package logs, independent IPA verification, screenshot provenance and named unmodified native PNG captures. Original Codemagic artifacts remain associated with the run above.

### Remaining gates and deliberately unavailable capabilities

This is an unsigned development candidate, not an App Store release or a completed physical-device qualification. SideStore signing/installation, LiveContainer compatibility, sustained iPhone RAM/thermal/battery/latency behavior, physical microphone/speech permissions and broader-model device switching/cancellation tests remain unverified. Catalog metadata and templates are checked for all nine downloads, but fresh full-weight native inference here covers the default Qwen model only.

External account integrations, autonomous scheduled execution, browser/computer control, hosted-site publishing and image generation remain explicitly unavailable. They are not simulated or represented as connected. Local projects, attachment organization, preferences, ordinary file import/export/share and available on-device inference are real. Small local models do not reproduce frontier-model quality.
