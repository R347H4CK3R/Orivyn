# Whole-request local-read proposal router

`LocalReadRequestRouter.js` exposes `OrivynLocalReadRouter.route(text)`, returning a JSON string:
`{status:"matched"|"needsClarification"|"unsupported",message:String,request:null|{appInfo:Bool,installedModels:Bool,searchQuery:null|String,memoryQuery:null|String}}`.

This is a small deterministic English pattern matcher, not a language model or general natural-language understanding. It only proposes a structured request; it never calls a tool or executes a read. Native must show selections for review/confirmation before starting VerifiedLocalPlan. Nonmatched requests always return request:null, never partially recognized actions.

Accepted examples:
- What app is this and what models are installed?
- Please show app capabilities and list installed local model names.
- Tell me about this app.
- What can this app do?
- Show this app's capabilities.
- Which local models are installed?
- Search my conversations for "USB and restore".
- Find conversations matching "do not delete" and show app info.

Matching uses anchored, explicit patterns for app identity/information/capabilities, installed-model names, and double-quoted exact conversation searches. Optional initial please and a final question mark/period/exclamation are recognized. Clause conjunction and is split only outside quotes. Every clause must match. Two different search queries require clarification; repeating the same selected read is harmless and deduplicated.

Bounds: input1024UTF8bytes, query256bytes. Invalid Unicode/control input, empty or unclosed query, unquoted query, explicit ambiguous pronoun patterns and conflicting search queries return clarification. Negated, unsupported, appended or side-effect clauses never produce a matched proposal. Unknown wording can be unsupported even if a human understands it; native should offer explicit selectors rather than guessing.

Double-quoted text is inert query data. Literal escaped double quotes and backslashes are decoded; other backslash characters remain literal. A query containing and, negation, or malicious instructions is still searched as data and never changes selected actions. This is not authority granted by quoted text.

13 real-code tests cover mixed clauses, exact quoted conjunctions, malicious data, missing quotes, bounds, whole-input rejection, negation, conflicting requests and bare JavaScript execution. RED/GREEN evidence saved beside tests. No production reducer/native changes, model runs, network requests, or device verification are implied.

Saved-memory full-phrase routing now supported; see MEMORY-READ-EXTENSION.md for schema and examples.
