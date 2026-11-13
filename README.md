# Orivyn private source checkpoint

Narrow changed-source backup for ongoing phone-only 1.0 development. This is not a release or a build-ready checkout. SourceCheckpoint contains 169 selected source and test files relative to the local integration baseline; unchanged dependencies and original resources are not included. VM binaries/vendor assets, models, archives, signing material, local logs and account state are excluded. No credentials were found by a targeted token/private-key scan; this is not a complete secret audit.

Latest local portable evidence: 132 Python, 70 agent JavaScript, 39 VM JavaScript tests passed. iOS compilation, native UI tests, physical iPhone verification and full 1.0 acceptance remain outstanding. No IPA, catalog update or automatic synchronization is claimed. This backup must not trigger paid builds.

Actual Foundation-only Swift 6.1.3 Linux validation: 235 selected XCTest cases passed from exact copied production sources. All 188 app/test Swift files passed syntax parsing; this is not iOS API/type checking or a full app build.

The Foundation validation subset includes its exact production/test dependencies. Most unchanged baseline files and full app dependencies remain omitted; this is still not a build-ready iOS checkout.

One extra Linux custom-URLProtocol redirect fixture is excluded after a confirmed unsupported corelibs fatal error; it remains required in the Apple gate. Hermetic MCP tests do not prove access to any actual external plugin service.

Observable journal/workspace tests compiled after actor-safe XCTest fixture repairs but cannot link against the official Linux Observation library (missing runtime symbol). They remain unexecuted and are retained in the Apple gate; the working Linux subset does not fake Observation.

Actual Swift RED/GREEN regressions now cover plugin numeric underflow and unsafe integral exponent forms. Unsupported values are rejected rather than silently changed to zero or rounded integers; remaining numeric semantics are IEEE-754, not arbitrary-precision decimals.

The 35 Markdown parsing/highlighting cases execute against exact production source on Linux. Five native layout, inline rendering and bundled math renderer tests remain in the separate Apple-only class; Linux success is not rendered-UI verification.

Dense code highlighting now has a 4,096-run ceiling and lossless plain-text fallback, verified RED (3 failures) then GREEN. Four incoming-text URL/draft tests and six reminder value-validation tests now execute on Linux; actual AppIntent/inbox, notification scheduling and permission behavior remain Apple-only.

Plugin schema keys and string enums now use exact Unicode codepoints rather than Swift canonical-equivalence matching. Five actual regression tests failed before the fix and passed after; values are not normalized or rewritten. Canonically colliding duplicate JSON keys remain conservatively rejected.

Model installation now uses a prepared on-disk journal, two-file publication and retained rollback copies, with nine real filesystem tests including partial rollback and retry. LocalModelStore is wired to recover before opening/reading. Apple file-protection/inference integration remains unexecuted. This is process-interruption recovery, not guaranteed power-loss durability. Model deletion now shares the journal/rollback transaction; six added filesystem tests cover failure boundaries, absence and recovery. Deletion/recovery now prefer same-volume hard links so large model bytes need not be duplicated; unsupported filesystems fall back to copies. A real inode/content regression failed before and passes after. Metadata and fallback copies still need free space; no universal low-disk guarantee.

Remote streaming value/parser types now execute unchanged production dependencies in the Foundation harness. Fifteen provider tests pass; two regressions failed with five assertions before CR/LF/CRLF framing repair. This does not verify iOS networking, actual provider access or full multiline-SSE interoperability.
