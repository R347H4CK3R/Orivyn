# Verification update — 2026-11-15 02:02 UTC

## Retained package, not published

Build 8 from a6c696a89a2e5a6224e220b6772b62614d30b4df is retained in GitHub release draft 445746248, tag candidate `orivyn-v0.1.1-build8`. It is a draft and prerelease; neither SideStore source was changed.

The retention workflow [43665558711](https://github.com/R347H4CK3R/Orivyn/actions/runs/43665558711) revalidated the source run, artifact identity, exact IPA hash, size, bundle version, minimum OS and SCOPE.json before creating the draft. IPA: 37,072,679 bytes; SHA-256 `04c2bd77eb6f807eb17c24bce6ff0a8cf88cae5d74e0e43955cba9230d01723d`. This preserves a development candidate, not completed 1.0.0 or device acceptance.

## New-conversation failure is intermittent

The unchanged application UI at f8bd5c06d3ae571d07d3756a9bd2dd332c662da6 passed all 17 ui-1 tests in job 132657347076 of [run 43663363822](https://github.com/R347H4CK3R/Orivyn/actions/runs/43663363822). In particular, `AutomaticRealInferenceUITests.testActualGeneralCoderDownloadSwitchAndRelaunch` passed in 270.202 seconds, including new-conversation transitions after actual inference.

This does not erase the prior failed transition at fb146910 or prove a fix: no production navigation change was made. The failure needs further reproducibility and lifecycle evidence. In the same f8 run, ui-2 reproduced the lazy-form `agent.create` lookup failure; 8ab97c4 contains the bounded scroll regression adjustment, whose native result is still pending.

## Live exchange test harness

The first end-to-end native exchange test run 43664779691 failed during compilation because the harness generated a SQLite3 module already supplied by the Mac SDK. No exchange checks executed. Isolated commit 159b121092e3e6753648dfb5a66fa3942fdd7e92 removes that duplicate module and uses the SDK module. Its run 43665507033 is pending.

Authenticated channel tests and portable packet/storage tests remain separate evidence. The proposed exchange adapter is not yet native-validated or enabled in the app. Pairing UI, lifecycle consent, unsaved-edit coordination, scheduling and physical-device validation remain incomplete.

## Real-model diagnostic did not complete

A second attempt of the nested-result baseline/decoded-results diagnostic exited 137 after printing the verified model and CLI hashes but before any completed decision. Cause is unconfirmed; this is not evidence for or against the hypothesis and not a passing model evaluation. No production prompt or acceptance threshold was changed.

CLI SHA-256: 847c7ba9b5fb3c2e204a0ac16a5d7a90e484430db4fcd2c83a1ecbdaa7b71ad5.
Model SHA-256: d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5.
