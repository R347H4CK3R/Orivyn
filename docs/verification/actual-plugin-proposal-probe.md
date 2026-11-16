# Actual local-model proposal acceptance probe

`ProductionChatPluginProposalTests/testPinnedModelSelectsExactPluginProposalWithoutPrivateContextOrExecution`
uses the existing pinned Qwen3 Q4 fixture through the production local adapter and
proposal coordinator. Its synthetic catalog offers different search/create
schemas. Acceptance requires one real model decision, a search proposal containing
the unpredictable exact phrase from the fresh user request, schema validation,
and no fallback. Caller history/system sentinels must not appear in the actual
model request. No broker, remote provider, or execution capability is supplied.

Diagnostics include synthetic requests, the parsed proposal, byte counts, errors
and bounded visible-only model output filtered independently by ChatAnswerStream.
Raw reasoning text is not retained. The observer worker is canceled and joined,
then the actual engine is unloaded and joined before releasing the fixture lock.
Cancellation or an unsupported/partial result cannot count as successful acceptance.

The new native test has been syntax-parsed only in this environment. It has NOT
run against the actual model yet. Existing portable suites remain green (602
Foundation, 154 Node, 278 Python tests with one skip); they do not execute this
native test or establish actual model quality, external-service safety, UI behavior,
or physical-device readiness. No CI or release was dispatched for this checkpoint.
