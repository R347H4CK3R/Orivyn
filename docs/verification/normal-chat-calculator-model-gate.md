# Real-model bounded arithmetic gate

`ProductionNormalChatCalculatorTests.testPinnedModelChoosesCalculatorAndAnswersFromVerifiedResult`
uses the existing explicitly enabled `ORIVYN_REQUIRE_NORMAL_CHAT_MODEL=1` pinned Qwen3 1.7B
Q4 fixture. It is a separate required native test (+1), serialized through the existing
fixture lock. It requires `NormalChatToolAction` and the bounded normal-chat arithmetic
implementation; it does not alter that implementation or existing memory/coding probes.

The fresh synthetic request is `Calculate 173 * 29 - 41`. An observer delegates every
inference unchanged to LocalAIProvider. The first model decision must choose calculate;
LocalReadTools executes with the exact trusted current goal. The real bounded arithmetic
parser produces the result, LocalCalculationEvidence recomputes it, and an independent
fixed test oracle expects 4976. The result is absent from the first inference and present
in the second. Exactly one successful operation and two model decisions are required.

The receipt journal is synchronized to disk before dispatch and checked on disk before
subsequent model inference. The final generated answer must give 4976 separately from
those receipts, use the unverified-interpretation boundary and not leak think delimiters.
Failure evidence is attached before rethrowing; no retries or scripted decisions are used.
The production 120-second loop deadline remains unchanged.

Local validation: Swift syntax parse only. Native typechecking and actual model execution
are pending. This does not establish physical-device performance, general arithmetic
reliability or general autonomous tool use. Add the class to the combined gate only after
its implementation dependencies are integrated; no separate CI was dispatched here.
