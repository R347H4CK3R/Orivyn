# Normal-chat structured context budget (local candidate)

Based on build18 plus local conversation-policy commit `7ab763b`.

## Root cause

Normal chat packed instructions, current goal, six history excerpts, and up to
three recorded results into one user message. The generic engine fitter removes
older messages, not subfields of that single message. Byte admission bounds did
not guarantee the fully templated prompt fit the 2048-token runtime context with
1024 tokens reserved for output.

## Change

`GenerationRequest.normalChatPrompt` carries structured normal-chat input to the
engine. The engine supplies its actual model tokenizer and complete formatter
(system prompt, chat template, concise prefill included). The fitter removes
oldest complete historical turns until the measured prompt fits, removing orphan
assistant messages too. Omitted-history count is explicit JSON data. It does not
truncate the trusted instructions, current user request, or validated recorded
results. An irreducible overflow returns a specific error explaining the local
context limitation; receipts remain durable and are not replayed. Output reserve,
read authorization, validation, and action limits are unchanged. Direct chat
continues to use the existing attachment/history fitter.

The serialization-only ceiling is 128KiB, separate from the unchanged runtime
context. This covers admitted payloads even when history controls and nested
result strings expand during JSON encoding. The previous 24,576-byte cap could
reject before tokenizer fitting. Oversize serialization failures now produce the
same actionable context error rather than a misleading plugin-response error.

## Local verification

- Initial regression compile failed because the structured fitter was absent.
- 623 Foundation Swift tests pass, including whole-turn eviction, formatted
  overhead, exact-boundary acceptance/rejection, Unicode/JSON preservation,
  hostile tool-result text retained only as data, irreducible-evidence rejection,
  tokenizer cancellation propagation, orphan removal, invalid reserve, and
  captured production request containing structured payload. Additional tests
  cover an admitted 4096-byte escaped goal, six 512-byte history excerpts, and a
  validated escaped list_models result whose envelope exceeds the old cap;
  serialization-cap failure; and a successful recorded read followed by fitting
  rejection, with exact one-read/no-replay event order and preserved evidence.
  The encoding regressions failed before the serialization fix (two failures).
- 297 Python tests pass with one existing skip after updating the engine-wiring
  assertion to check both branches share the actual formatted-token counter.
- `git diff --check` passes.

No GGUF fixture or Apple runtime was available here. Unit tests inject a counting
closure; the production engine wiring calls llama's tokenizer, but native build,
real-tokenizer inference, simulator/device behavior and actual-model quality are
NOT validated by these local results. No release, upload, or CI was performed.
