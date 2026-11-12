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

Authored source contains 288 native test methods and 26 UI test methods. Counts are not execution results. Xcode/xcrun is unavailable in this Linux workspace. The authorized free Codemagic build must compile, run the real-weight checks and UI suite, inspect captures, and verify the physical-device ARM64 package before completion is claimed.

The previously successful build 3, on CI commit `fa3c7bc65eaf363835f8f30f2243154971058802`, verifies only the recovered baseline. Its unsigned IPA was 2,945,869 bytes, SHA-256 `2d1541c319e26397e8032ee565e57bac03ae49a05cd1b8cfaef1896af7842b7f`. It does not verify this reconstruction. No release, signing, physical installation or actual iPhone performance is claimed here.
