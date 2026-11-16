# Normal-chat connected-tool proposals

This increment prepares a suggestion, not an external action. When normal Send
has resolved a concrete on-device model and an already connected plugin catalog,
a separate local inference sees only the fresh typed goal and bounded catalog
schemas. It does not see conversation history, saved memories, files, location,
credentials, prior tool evidence, or the normal chat system prompt. No new
connection, discovery, installation, remote inference or tool request is made.

The model returns one schema-validated proposal or `unsupported`, which continues
the existing normal-chat three-local-read loop. Invalid/unknown output fails
closed rather than being interpreted as a command. Existing deterministic local
reads, remote providers and externally sourced drafts keep their existing paths.
There is a local inference latency cost for eligible connected-plugin chats.

## Approval boundary

The proposal is an in-memory typed object bound to generation, assistant,
conversation revision, provider revision, connection and catalog revision. It
expires after five minutes. The displayed message is not parsed as a proposal or
replayed after restart. The route revalidates the live schema and all bindings.
The UI consumes the matching pending card only after obtaining the route and
serializing its arguments; the frozen route retains existing review guards.
Existing `PluginToolCallView` still requires Review exact call and Run reviewed
call. Only PluginBroker may consume the expiring one-use approval and write its
journal before sending. Tool read-only annotations never grant approval.

## Limits and verification

Catalog limit: 64 tools, 32 KiB encoded schemas, byte-exact unique names. Fresh
goal: 4096 UTF-8 bytes. Raw model output (including hidden reasoning): 16 KiB.
Arguments retain existing schema/16 KiB review limits. Deadline is cooperative:
The proposal stage has 120 seconds; an unsupported result lazily starts a fresh
120-second local-chat budget (at most 240 seconds combined). These deadlines
request cancellation, not hard termination of an uncooperative model. Cancellation and revision changes prevent publication/continuation.

Portable tests exercise real schema validation and adapter transitions using
controlled model streams; these are not proof of actual model selection quality.
The native AppModel regression is syntax-checked only until an Apple gate runs.
Physical iPhone, external provider, review UI and real model behavior are unverified
for this new increment. No automatic external calls, general plugin autonomy,
or release readiness is claimed.
