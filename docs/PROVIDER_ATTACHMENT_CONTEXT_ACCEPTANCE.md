# Remote/system attachment prompt integrity

OpenAI-compatible and Apple system providers use `ChatMessage.promptContent` and `ContextWindow`, rather than the local model's prompt builder. Review found that this path silently omitted unavailable document text, left empty OCR without an availability explanation, clipped long excerpts without disclosure, and skipped saved/imported messages whose typed content was empty even if they contained attachments.

The fix keeps whole-message context limits and the existing 20,000-character per-attachment excerpt cap. Missing or whitespace-only extracted text is described as unavailable, images retain the explicit text-only/no-pixels limitation, and shortened excerpts are marked. Context selection counts the actual prepared message, including these notices. It preserves original records and still omits failed messages. No automatic upload, OCR execution, remote call or model capability is added.

Verification uses exact Foundation production code. These tests do not execute Apple's FoundationModels framework, contact an online provider or verify inference obedience to the notice. Native provider/device acceptance remains outstanding.

Verification:6 focused tests reproduced15 failures before the fix, then passed. Full Foundation suite passed298 tests, including7 previously unexecuted ConversationTests plus6 new context tests.135 Python,74 agent Node and39 VM Node tests passed. Independent source review found no concrete regression. Private checkpoint c830a572ec7e949ad14e2a7d2d46513745c9db03 exact source fetch verified; no IPA or release/catalog changes.
