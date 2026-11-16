# Bounded natural local reads

This increment adds deterministic natural-language routing, not model-selected
tools or general agent autonomy. It does not call a model, download anything,
invoke a plugin, browse, write data outside normal chat persistence, or contact
a remote endpoint.

## Actual supported grammar

In addition to existing direct local commands, these whole clauses are recognized
case-insensitively (a final question mark is optional on the fixed questions):

- What models do I have?
- Which models are installed?
- What models are installed?
- What can this app do?
- What can Orivyn do?
- Tell me about Orivyn
- Find QUERY in my saved memories
- What do you remember about QUERY

The original query text is retained, including Unicode, case and apostrophes.
Existing query validation and the 256-byte limit still apply. A question mark
inside a memory query remains query data. No new polite "can you", "could you",
or "please" aliases are added; existing direct-command behavior is unchanged.

Up to three distinct reads may be joined with "and", "then", "and then", or ";"
only when every clause parses. A memory search must be last. A whole memory
clause is parsed first, so "Find bread and butter in my saved memories" keeps its
query intact. The compound "What models do I have and find bread and butter in
my saved memories" is ambiguous and deliberately declines tool routing rather
than truncating or rewriting the query.

Only the current composer text is parsed. Attached files, history, imported
memory, plugin metadata, quoted command envelopes, negation, ordinary coding
requests and unsupported clauses cannot grant scope. Unknown input stays ordinary
conversation. A declined tool route is not a promise that the chat model will
answer well.

## Execution and verification

Existing bounded real read adapters execute the resulting contract. The normal
Send path checks captured conversation and provider revisions before and after
each read, including switch-away-and-back changes. Stale/cancelled work is marked
interrupted; completed prior evidence can remain visible. Evidence limits and the
three-tool allowlist are unchanged.

Portable tests cover actual parsing, preserved query bytes, ambiguity, control
text and bounded scope. Native AppModel tests additionally cover real read
dispatch, persisted results, conversation/provider invalidation and coding text
remaining normal conversation. Those native tests require Apple execution and
are not claimed verified by the Linux suite.

Potential later work: evidence-grounded local answer synthesis could be useful.
A model call solely to reorder independent reads adds latency and failure modes
without a user benefit, so it is not included here.
