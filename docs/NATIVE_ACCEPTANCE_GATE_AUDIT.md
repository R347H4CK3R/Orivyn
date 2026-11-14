# Native acceptance audit

Manual run_virtual_desktop_gate.sh downloaded optional test weights but did not force LocalInferenceTests to fail if those weights were unavailable to the test runner. It now passes JARVIS_REQUIRE_REAL_INFERENCE=1, matching ci_macos.sh, and explicitly selects AutomaticPreparationTests and PluginBrokerTests. A configuration regression failed before and passes after. The full Python suite passes134tests.

Two remaining @MainActor test classes used synchronous nonisolated setUpWithError/tearDownWithError while accessing isolated fields. The exact class headers, stored properties and hook bodies were extracted into a temporary XCTest-only file (app-dependent test methods/import omitted). Actual Swift6.1.3 typecheck failed with actor isolation errors. Changing the real classes to async setUp/tearDown made the isolated hook typecheck pass. This is NOT a typecheck or execution of either complete native test class. All188Swiftfiles syntax-parse.

The extracted repro is reproducible by taking each file from @MainActor through before its first test method, adding a closing brace and importXCTest, then swiftc -swift-version6 -typecheck with a writable module cache. Before/after sources and compiler logs are retained in /tmp/orivyn-actor-fixtures-{before,after}.swift/.log.

## Remaining release blockers

- Actual Xcode26 iOS app build and simulator test run, with real local inference required. Linux241selectedXCTest cases do not substitute for native app acceptance.
- Physical iPhone installation through SideStore and actual voice, background behavior, memory/thermal limits, external display, camera/Photos and local-model checks.
- Broad autonomous model-driven tool use failed prior semantic tests; deterministic verified local reads are a distinct supported mode, not a claim of general autonomy.
- Automatic cross-device synchronization and self-applied/rebuilt code repair are not completed; existing manual transfer/read-only repository inspection must remain labeled.
- Actual external-provider/plugin integrations require configured services and permissions; parser tests prove no remote account functionality.
- Private checkpoint is selected-source recovery, not full build-ready checkout. Native build resources/dependencies must be assembled and verified separately.

No version1.0.0 readiness, IPA publication or catalog update is claimed by this audit.

## Latest source-wide syntax check

A fresh Swift 6.1.3 frontend parse of all 214 app, unit-test and UI-test Swift files completed with zero syntax failures. Each file hash and command result is recorded in `source-parse-audit-20261113/results.json` in the local validation evidence. This does not resolve imports, type-check Apple SDK declarations, link an app, execute simulator tests, or validate a device.

The latest full portable Foundation suite is 312 passing cases; earlier counts above describe historical runs. The selected private source checkpoint remains separate from a complete buildable release checkout. No simulator or IPA verification was added by this check.
