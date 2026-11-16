# Normal chat: bounded model-selected local reads

## Scope and architecture

This increment is not another fixed command alias. For a fresh normal Send on
an installed concrete LocalAIProvider, the local model can answer immediately or
choose a real local read, inspect the returned evidence and continue. Automatic
mode uses the same wrapper only after its existing authorized preparation has
resolved a concrete LocalAIProvider. No extra download, provider switch or remote
fallback is added. Nonlocal factory/provider results stay ordinary conversation.

The entire allowlist is DirectChatRead: get_app_info, list_models, search_memory.
The model can pick a relevant saved-memory query. Queries are limited to 256
UTF-8 bytes, search results to 1..3. No calculator, history search, original
attachment, plugin, remote endpoint, write, installation or external action is
available in this loop. Those existing separately reviewed workflows are not
silently widened.

Typed LocalCompletionContract.Action validation and existing
LocalCompletionPolicy result validation are reused. A restricted grammar allows
answer or only the three advertised reads; semantic validation remains the
authority. The manual LocalAgentSession reducer/recovery formats are unchanged.

## Origin and user disclosure

Eligibility is based on a fresh composer turn, not old conversation instructions,
a decoded model plan, a backup or a tool result. Imported shared text and plugin
result drafts are tainted until explicitly cleared; editing does not silently
untaint them. Failed initial persistence restores the taint along with the draft.
The same source guard applies to deterministic direct reads.

Attachments, quoted/code envelopes and explicit no-read/no-tools requests use
ordinary chat. Explicit no-memory phrasing also excludes saved-memory context
from the ordinary provider request. Tool adapters do not preload unrelated memory
context outside their own reads.

The composer caption is integrated by a separate UI commit using
automaticLocalChatReadsAvailable. Its wording states the local data classes and
that read receipts appear in chat. Exact direct-read captions use the shared
currentDirectLocalReadContract eligibility.

## Evidence and durability

Before a read starts, the provider awaits a started-event recorder. After a
successful bounded/validated result, it awaits the success-event recorder before
requesting the next model decision. The AppModel recorder is bound to the exact
assistant message and conversation/provider revisions, appends a delimited
receipt and awaits the existing SQLite save. Failure to acknowledge a save stops
work. The usual quarter-second token checkpoint is not this barrier.

Receipt text is display-only, never parsed as authority or replayed. It is not
cryptographic provenance and remains editable as conversation data. The final
model answer is separately labeled after reads; reserved app-receipt markers in
model answers fail validation before display. No private reasoning text is saved.

Conversation/provider switch-away-and-back, cancellation and stale message
ownership are checked before/after inference, persistence and reads. A retained
started event without a result means unknown/interrupted, not success. There is
no automatic crash replay or resume.

## Bounds

- At most three read dispatches and four model decisions.
- An identical validated call cannot repeat.
- Each result <=4096 bytes, cumulative results <=12288.
- Raw inference including hidden reasoning <=16384 bytes per decision.
- Answer <=4096 bytes; goal <=4096.
- Conversation data: last six messages, each <=512 bytes with truncation flags.
- Encoded model context <=24576 bytes; no silent result truncation.
- Receipt serialization <=16384 bytes including escaped evidence.
- A 120-second cooperative deadline races work and propagates cancellation.
  It is not a hard kill of a noncooperative provider; no subsequent dispatch can
  pass the cancellation/origin checks.

## Verification boundary

Portable tests cover state transitions, call selection/answer-only flow using a
controlled provider, actual grammar-resource parity, strict schema/result checks,
receipt acknowledgement ordering/failure/cancellation, duplicate/read/token
bounds, injection attempts and forged receipt rejection.

Native tests cover actual SQLite acknowledgement, origin ABA changes, imported
draft retry provenance and Automatic concrete-local selection. They require
Apple execution and are not verified by Linux syntax parsing. The additional
pinned-model semantic gate must prove an actual model chooses a real memory read
and answers from its synthetic evidence; scripted-decision tests do not prove it.

No build, device result or release readiness is implied by this implementation.
