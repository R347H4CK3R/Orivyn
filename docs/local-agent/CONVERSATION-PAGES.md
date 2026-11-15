# Bounded conversation follow-up reading

The local agent can now inspect stored message text after finding a conversation. Previously `search_conversations` returned only a short excerpt, preventing a follow-up read of the surrounding messages.

`read_conversation {"id":"ID returned by search_conversations","messageIndex":0,"offset":0}` returns one page of up to 512 UTF-8 bytes from one saved message. `next` gives the next message index and byte offset, or null at the end of the accessible message window. The response includes message identity, role, state, byte count and truncation flags. Failed/interrupted saved assistant text remains labeled as such and is not verified factual evidence. Attachment contents and paths are excluded, with an explicit omitted attachment count.

The reducer admits only IDs in a preceding successful search result; it checks this again when validating restored pending and completed records. The native dispatcher independently derives allowed IDs from the saved search history. IDs that were not returned, deleted conversations, streaming messages, invalid indices, oversized messages, or offsets inside a UTF-8 scalar are rejected. Current saved in-memory app history is read under the existing exclusive local-agent lease. Pages are not an immutable snapshot across resumed tasks or later runs; the prompt explicitly identifies current-history semantics and requires disclosure of messageTruncated and messageWindowLimited. No filesystem, network, write, or external tool capability is introduced.

Existing explicit Create/Run controls, six native-tool-call limit, 4096-byte result limit, 3500-byte prompt bound, durable pending-before-dispatch ordering, interruption recovery and saved-result exposure checks remain. Message indices are bounded to 0...9999, byte offsets to 0...1000000. Reaching a limit is not a claim to have read a whole conversation. This addition belongs to the existing bounded local-agent JSON flow; it does not expand the separate native two-metadata-tool suggestion bridge.

## Portable verification

- `node --test scripts/agent-tests/*.test.cjs`: 108 passed, including new search provenance, forged/unreturned IDs, restored-state provenance and shared step-limit tests.
- `python3 scripts/run_foundation_tests.py --swift /path/to/swift --output /new/evidence`: 405 passed on Linux/Swift 6.1.3, including five conversation-page tests covering native provenance, deleted/streaming conversations, Unicode reconstruction, malformed cursors, JSON escaping, attachment exclusion and empty/end boundaries. The existing Linux URLProtocol redirect exclusion remains.
- The updated GBNF parsed successfully with the pinned llama b9049 grammar parser (29 rules); this is syntax validation, not a model-obedience test.
- `python3 scripts/run_conversation_read_smoke.py --swiftc /path/to/swiftc --output /new/evidence`: compiles the actual LocalReadTools dispatcher and Foundation types, supplies only an AppModel data scaffold, then passes actual Swift search/page payloads through the production JavaScript reducer and recovery. It records source hashes and explicitly does not run model inference or the iOS app.

The first Foundation run exposed a test-helper issue: XCTUnwrap recorded expected negative-test throws as failures. The helper now evaluates the throwing read before unwrapping its successful result; no production validation was relaxed.

No iOS runtime, simulator, physical-device, or real-model choice/reliability claim is made for this extension. The existing native Qwen ARM expiration remains unresolved and its deadline is unchanged.
