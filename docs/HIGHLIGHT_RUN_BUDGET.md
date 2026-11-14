# Code rendering run budget

Independent exact-production Swift audit found a 100,000-byte valid code block generated 100,000 syntax tokens. The native view builds an attributed text run for every token, so byte limits alone did not bound native rendering allocations. This was not a measured iOS stall.

Added maximumTokens = 4,096 with an early full-source plain-text fallback. Each lexical iteration may flush one pending plain token plus one styled token, so the guard reserves two slots. All source characters remain available. Independent review confirmed no output overshoot.

Two new actual Swift regression methods (dense numeric/keyword code, boundary run counts, exact joined-source preservation) failed with three assertions before the fix; after it all 199 selected XCTest cases pass. Proof manifests and logs are retained in proof-17-highlight-red and proof-18-highlight-green. 132 Python tests pass and 183 Swift files syntax-parse.

Also extracted IncomingTextRequest and its errors unchanged from the Observable inbox and moved its four existing URL/draft tests into a Foundation-only class. Six existing local-reminder value-validation tests moved into their own class. These execute real production code without faking Observation, AppIntents or notification frameworks. Native inbox, shortcuts, notification scheduling/permissions, rendering and math-resource tests remain in the Apple gate and unexecuted here.

No new IPA, catalog update, native performance claim or full 1.0 completion claim.
