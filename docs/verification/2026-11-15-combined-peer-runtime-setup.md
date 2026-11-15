# Combined peer sync gate: first successful compile and failed runtime setup

Source `c3eb54f7f0d3868c2f9485c9954e0a57d12455fc`, [run 43682583169](https://github.com/R347H4CK3R/Orivyn/actions/runs/43682583169), job `132716188477`:

- Actual iOS device-target and simulator-target application compilation both succeeded with the experimental peer flag enabled. This resolves the prior compiler-crash gate for that source, not runtime/device acceptance.
- All 11 history-owner/recovery tests and four negative session-policy tests passed in the iOS simulator.
- All four real-identity session test bodies were prevented by Keychain setup failure `keychain(-34018)`; setup and teardown produced eight failures. XCTest reported four skipped bodies. These are failures, never passes.
- The native transport phase executed no cases: its runner was invoked without the required evidence-directory argument.
- Artifact `14149786160`; ZIP SHA-256 `ac51480ee0d37fa4e1018886b22f0712105102a5e857a1174df231fbb6cfcc6b`.

Apple documents -34018 as a missing entitlement and recommends inspecting the actual built code signature. See [Apple's Keychain troubleshooting guidance](https://developer.apple.com/forums/thread/114456) and [Keychain access groups](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps).

## Next isolated gate changes

The simulator test host is ad-hoc signed with a test-only application identifier and Keychain group, and its built signature and entitlements are verified before test execution. No developer account, device provisioning profile, distribution signature, shipping entitlement or production identity changes are introduced. Actual Keychain APIs remain required; tests are not skipped or replaced.

The app gate selects 22 cases: 13 history checks, four negative session checks, four real-identity session checks and one actual two-session/AppModel/Keychain/SQLite/TLS loopback test. It requires all 22 to pass, with no skipped tests. The loopback case includes real idle time; it is not a two-physical-device test.

The native gate receives its required evidence directory and requires all 40 cases (8 authentication, 7 channel, 17 exchange, 8 automatic-controller). A separate Security storage probe and four real identity-provider tests are also included. Every phase preserves its evidence even if another phase fails.

All these fixes remain candidates until the new gate finishes. The production peer feature flag stays off. No release is produced by this workflow.
