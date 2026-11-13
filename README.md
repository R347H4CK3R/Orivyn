# Orivyn private source checkpoint

Narrow changed-source backup for ongoing phone-only 1.0 development. This is not a release or a build-ready checkout. SourceCheckpoint contains 151 selected source and test files relative to the local integration baseline; unchanged dependencies and original resources are not included. VM binaries/vendor assets, models, archives, signing material, local logs and account state are excluded. No credentials were found by a targeted token/private-key scan; this is not a complete secret audit.

Latest local portable evidence: 132 Python, 70 agent JavaScript, 39 VM JavaScript tests passed. iOS compilation, native UI tests, physical iPhone verification and full 1.0 acceptance remain outstanding. No IPA, catalog update or automatic synchronization is claimed. This backup must not trigger paid builds.

Actual Foundation-only Swift 6.1.3 Linux validation: 149 selected XCTest cases passed from exact copied production sources. All 178 app/test Swift files passed syntax parsing; this is not iOS API/type checking or a full app build.

The Foundation validation subset includes its exact production/test dependencies. Most unchanged baseline files and full app dependencies remain omitted; this is still not a build-ready iOS checkout.

One extra Linux custom-URLProtocol redirect fixture is excluded after a confirmed unsupported corelibs fatal error; it remains required in the Apple gate. Hermetic MCP tests do not prove access to any actual external plugin service.

Observable journal/workspace tests compiled after actor-safe XCTest fixture repairs but cannot link against the official Linux Observation library (missing runtime symbol). They remain unexecuted and are retained in the Apple gate; the working Linux subset does not fake Observation.
