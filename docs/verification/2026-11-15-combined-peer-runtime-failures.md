# Combined peer sync runtime gate: three separate failures

[Run 43685006410](https://github.com/R347H4CK3R/Orivyn/actions/runs/43685006410), source `76e0732d2941f82381480960dc95841fdd6581a1`, job `132723538182`.

Artifact `14150193092`, 200,021 bytes, ZIP SHA-256 `b998a7546bf6047c996dd5e8eeb0898baa09cf81fd8384ad83fb17b7c609ab7e`.

## Actual application compilation and simulator harness

Device-target and simulator-target application compilation both passed with the experimental peer feature flag enabled and exact dependency revisions verified.

The subsequent signed simulator build-for-testing failed before any of the selected 22 tests ran. The command-line `CODE_SIGN_ENTITLEMENTS` setting propagated into the `swift-certificates` package's `_CertificateInternals` target. Its relative path resolved inside the dependency checkout, where that file does not exist. This is a test-build configuration error, not evidence that real Keychain access or session transfer succeeded.

The corrective candidate removes the global entitlement override. A CI-only XcodeGen specification adds the entitlement path solely to the JarvisEVO application target. Actual signed-host entitlements remain checked before test execution. No shipping project signing settings or feature flags change.

## Native transport

The artifact contains 38 recorded passes:
- 8 mutual-authentication cases;
- 7 authenticated-channel cases;
- 17 request, receipt and authenticated-busy validation cases;
- 6 automatic-controller cases, including idle renewal and local busy deferral.

The automatic-controller fixture then raised `GateError.failed("fixture listener failed")` and the process exited 133. The last two planned cases did not produce results. The 40-case acceptance gate did not pass. No retries or reduced case counts are permitted to conceal this failure.

## Identity provisioning probe

The Security-only certificate storage probe segfaulted (exit 139) before emitting its JSON. Its captured storage log is empty. The full four identity-provider cases were never reached. This failure is separate from the simulator entitlement-path error and the native listener fixture failure.

The next coordinated gate must retain these failures and independently verify each correction. A successful build alone cannot enable the shipping sync feature or establish physical-device acceptance.
