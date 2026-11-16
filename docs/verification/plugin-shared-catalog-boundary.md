# Shared proposal catalog boundary

The normal-chat adapter and MCP discovery already reject duplicate tool names.
The shared PluginToolProposal prompt/parser API did not: direct callers could
supply an ambiguous catalog, and parsing selected the first matching schema.
This is defense in depth for the shared API, not a demonstrated UI bypass or an
external call; proposal generation still grants no execution permission.

Prompt and parser now reject byte-exact duplicate names consistently with their
byte-exact lookup. Catalog count is checked before allocating the name set, using
the existing 64-tool prompt limit. Direct generation validates before any provider
request. Tests cover duplicate prompt input, normal and unsupported parse output,
provider non-invocation, and an oversized direct-parser catalog.

Before the change, exact-source Foundation tests reproduced duplicate acceptance
and unwanted provider invocation. No approval, broker, prompt text, catalog schema,
or user-data handling was relaxed. Native/device/model and release verification
are outside this portable change; no hosted or paid resources were started.

Final portable aggregate passed 607 Foundation, 279 Python (one existing skip),
154 agent and 39 VM tests, plus catalog and guest validation. SQLite persistence
was not supplied and remains skipped; Linux URLProtocol redirect remains excluded.
Independent review found no blockers. Retained proof: /tmp/orivyn-duplicate-final.
