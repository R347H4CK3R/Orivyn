# Portable checkout verification — November 14, 2026, 18:44 UTC

Source: `57b67028e2ac90ca7d5add41ad9bda05d7900554` plus the runner/test changes in this commit, on `codex/portable-stream-validation-20261114`. The active native-capabilities branch and published IPA were not changed.

## Observed failure and repair

A fresh clone failed `test_bundled_guest_bytes_and_native_allowlist_agree`: the ignored `JarvisEVO/Resources/VMAssets/maintained.img` did not exist. Initial Python result: 161 tests, one error, one skip. Native CI already materializes the pinned compressed fixture; the portable entry point omitted that preparation.

Running the existing offline `scripts/materialize_guest.py` resolved all four VM integration contracts. The new runner regression then failed in both success/failure subcases before implementation. The repair adds a logged `guest` stage before Python contracts, using the existing archive/disk checksum and size checks. A preparation failure remains an overall failure while independent checks continue. No downloads or test exclusions were added.

## Fresh results

Ran `python3 -B scripts/run_portable_checks.py --swift /unavailable/swift --output /tmp/orivyn-portable-20261114-1848 --stage-timeout 120` on Linux. The unavailable Swift path was deliberately explicit after confirming Swift was absent from PATH.

| Stage | Observed result |
| --- | --- |
| Guest materialization | Passed; pinned archive and expanded-disk verification completed |
| Python | 162 tests executed: 161 passed, one existing real-tokenizer test skipped |
| Model catalog | Passed |
| JavaScript agent | 104 passed, zero failures/skips |
| JavaScript VM | 39 passed, zero failures/skips; host components only |
| Foundation Swift | Failed to start compiler: Swift unavailable; no Swift-test pass claimed |
| SQLite persistence | Skipped: no amalgamation supplied |
| Overall runner | Exit 1, status failed, correctly retaining unavailable-stage evidence |
| Diff whitespace | Passed |

The seven portable-runner tests are included in the Python total. Source-manifest, logs and SUMMARY.json were retained in the command's output directory. These counts are suite results, not distinct app acceptance criteria.

## Separate live CI and release evidence

GitHub Actions run [43628047718](https://github.com/R347H4CK3R/Orivyn/actions/runs/43628047718), source `415fbceaa55aacb68bae5062bb4123111fa50019`, had passed combined native runtime verification in both jobs at this check. App tests/packaging and real production vision/tool inference were still running; neither job had passed overall. The earlier DEBUG-fixture compiler failure has a source correction, but its successful native test outcome is not yet established. These are different source revisions from this portable repair.

Latest public preview remains [0.1.1 build 6](https://github.com/R347H4CK3R/Orivyn-Distribution/releases/tag/orivyn-v0.1.1-build6). Its package was independently verified in the previous progress check; it was not rebuilt or republished here. No new IPA, simulator screenshot, physical iPhone, SideStore, voice/audio, HDMI, visual-parity or 1.0.0 acceptance result is claimed.

This was one scheduled work session, not continuous background execution. Next objective: inspect the exact newer CI results, repair demonstrated failures, and keep implementation/component evidence separate from native/device acceptance.
