# Actual Swift validation without paid CI

Official Swift6.0.3 Linux (x86_64) was downloaded from download.swift.org and executed locally. ArchiveSHA256:09d0a53fbddf2878673dd12c1504e7143c788f195caec9f2329740946eba525c. HTTPS vendor provenance and local checksum were recorded; no detached-signature verification is claimed.

## Verified

An isolated Swift package copied exact production files and unchanged XCTest files for AttachmentTextSearch, LocalSearchExcerpt and UTF8TokenAccumulator. Swift compiled them and ran25 tests with0failures. This replaces source-only confidence for those Foundation algorithms with actual Linux Swift execution, not Apple-platform behavior.

All175 Swift files under JarvisEVO, Tests and UITests also passed swiftc -frontend -parse. The first parse exposed a real syntax error in VerifiedLocalPlanCoreTests.swift (two declarations on one line); inserting a newline repaired it and the complete parse then exited0. Syntax parsing does not resolve iOS APIs or prove type correctness.

Full portable suite:132Python/70agentJS/39VMJS passed. The first Swift package attempt failed because default compiler caches were outside writable directories; the harness now isolates cache/config/security paths. That failed log is retained. The second run passed.

## Reproduce

Use an existing free Swift6 toolchain, with no dependency downloads or CI dispatch:

    python3 scripts/run_foundation_tests.py --swift /path/to/swift --output /new/isolated/directory

The output directory must not already exist. It preserves copied-source SHA256 manifest and complete compiler/test log. The module is deliberately named JarvisEVO so original @testable imports work. Only three Foundation-only production files are included; it is not a replacement app project.

## Still blocked

No Apple SDK, SwiftUI/UIKit/JavaScriptCore iOS compile, simulator launch, physical iPhone/HDMI verification, unsigned ARM64 IPA, or1.0release is established by these results. No paid CI was used. The private source checkpoint remains a narrow source backup, not build-ready app checkout.

## Expanded execution

The next isolated run (proof-04) compiled12 exact production source files and executed102 XCTest cases with0failures, covering model routing/catalog, native-tool suggestions, mail/calendar/browser draft validation, feedback URL validation, memory selection/search and stored-memory Codable compatibility, plus prior search/decoder algorithms. MemoryNote was moved unchanged from Conversation.swift to its own Foundation-only file; XcodeGen includes the entire source directory and two schema round-trip tests verify the existing persisted format. No database migration is introduced.

All177 current app/test Swift source files pass syntax parsing.132Python/70agentJS/39VMJS still pass. These are Linux algorithm tests: they do not send email, create calendar events, download/load actual AI models, execute iOS UI, or validate device integrations. Foundation semantics can differ from Apple's runtime; iOS gates remain required.

The private checkpoint now includes every source/test dependency of this isolated harness so that this validation subset is reproducible from the backup. It remains incomplete for building the full iOS app.

## Plugin protocol/transport expansion

proof-06 compiled the exact production MCP JSON/schema/client/transport sources and ran142 selected Swift tests with0failures. Minimal conditional FoundationNetworking imports and a Linux-only guard around the unavailable waitsForConnectivity setter enabled this; Apple transport configuration and permission policy are unchanged. Tests use hermetic stub/URLProtocol fixtures, not real external plugin services or credentials.

One additional test is explicitly excluded only by the Linux harness: MCPURLSessionTransportTests.testRealAdapterRefusesRedirectWithoutSendingCredentialToTarget. An isolated execution confirmed current corelibs Foundation crashes with `Fatal error: The URLSession swift-corelibs-foundation implementation doesn't currently handle redirects directly.` Exit1/signal4 and the full failed log are retained. This is an unsupported custom-URLProtocol redirect fixture, not evidence of iOS redirect success. Both MCP test classes, including this exact redirect test, are included in the Apple manual gate. Do not count the excluded test as passed.

Current totals:142 actual Linux Swift tests passed, one additional Linux fixture unsupported;177 Swift files syntax-parse;132Python/70agentJS/39VMJS pass. All iOS API/type/UI/device gates remain outstanding. No paid CI or release.

## Approval-gate coverage and observed toolchain limit

Swift6.1.3 Linux expanded the working subset to149 passing tests, including exact plugin approval capability/expiry rules and bounded source-diagnostic hints. Its official archiveSHA256 is28e4b24adf9b1b782b75919d9f2a0b0ad7e16e843aaa203e0baca780248dcdd6. The additional redirect-fixture probe also confirms the same unsupported Foundation callback under6.1.3; it remains excluded only on Linux and required on Apple.

Attempting real Observable workspace/journal tests exposed genuine Swift concurrency compile errors in synchronous XCTest setup/teardown. Those fixtures now use actor-safe asynchronous setup/teardown and test methods. Production persistence/approval semantics were not weakened. PluginJournalTests were split into their own file, preserving every assertion and including the class in the Apple gate.

After that repair, the expanded target compiled but could not link: both official Swift6.0.3 and6.1.3 Linux Observation libraries reference an absent `swift::threading::fatal` symbol. Failed proof-07/08/09 logs are retained. No fake runtime symbols, replacement Observable behavior, or unsupported-success claims were used. Observable journal/workspace execution is therefore still unverified and excluded from the working Foundation subset. All those tests remain in the Apple gate.

The current working subset has149 passing Swift tests;178 Swift files syntax-parse,132Python/70agentJS/39VMJS pass. Full iOS type checking, simulator/device behavior and release remain outstanding. A source audit also found similar synchronous lifecycle patterns in AutomaticPreparationTests and PluginBrokerTests; those are not yet executed or repaired by this pass.
