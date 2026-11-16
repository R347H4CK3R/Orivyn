# Conversation response boundary

Scope: ordinary chat, not agent JSON decisions, imported history, or tool execution.

Reported failure: a Python-writing request returned an app-only refusal and exposed a leading `<think>` block. Source inspection confirmed ordinary chat appended provider text directly into the displayed/persisted message. The old prompt discussed execution limits without explicitly distinguishing writing code from running it. This makes the prompt a candidate contributor, not proof of the model's internal cause.

Changes:
- General-purpose conversational policy explicitly permits Python/code drafting without claiming execution, asks for direct non-echo replies, and forbids invented tools/action results.
- Leading `<think>…</think>` is treated as a model channel. Its contents are not persisted, spoken or displayed. Delimiters may be split between streaming chunks. Incomplete confirmed reasoning produces no successful answer.
- Answer whitespace/indentation and subsequent literal tags in code remain intact. Literal leading `<think>` is ambiguous and reserved for the channel; quote or code-fence literal examples. This does not parse every possible model's reasoning protocol.
- No existing conversation content is deleted or rewritten.

Tests distinguish deterministic contract correctness from model quality. Foundation tests exercise chunk boundaries, incomplete output, Unicode, code literals and indentation. Native AppModel tests exercise prompt propagation and SQLite answer-only persistence but require Apple execution. No actual-model Python/no-echo result or iPhone behavior is claimed by these tests.

Tools audit: ordinary chat is not a general autonomous tool loop. The local task bridge recognizes bounded read requests and opens review. PluginBroker discovers tools only from a configured endpoint and requires exact-call review; it does not independently discover arbitrary servers, install binaries or grant credentials. A prompt must not invent those capabilities.

No release or 1.0.0 completion is established by this change.

Verification in this workspace:
- Exact-source Foundation harness: 523 tests passed, including 8 response-policy cases. Linux excludes one unsupported URLProtocol redirect fixture; Apple remains required.
- Python `scripts/tests`: 271 tests, 4 failures, 4 errors, 1 skipped. Outstanding: attachment fitting source contract, explicit model gate all-success (plus three gate errors), persistence import UI contract, import picker fixture contract, missing bundled VM asset error. These are not marked passing.
- Extra top-level `scripts` discovery: stale backup-host expected counts (152 vs164, 28 vs30) and missing jinja2 for native-transcript test.
- Native AppModel tests added, not executed; no model semantic benchmark, no new IPA, no device acceptance.
