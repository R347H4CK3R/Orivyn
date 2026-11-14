# Scoped source knowledge and reviewed navigation

The old bundled prompt and manifest said the app could not inspect private source at all, contradicting the implemented Settings > Inspect private source screen. The prompt now separates explicit user-authorized read-only source inspection from chat access and executable self-repair. Self-repair, general visual understanding and native VM readiness remain unavailable; experimental VM development is described without claiming iPhone verification.

An injected metadata/version/provider prompt overload allows exact production Swift execution without a fake Bundle. Two tests cover correct scope and missing-metadata fallback. Actual cached model tokenizers measure the complete default system prompt at308–327tokens, below384, for nine cached model files. No estimated tokens substituted.

A real cached Qwen2.5 1.5B CPU run still answered the source-screen question with a generic refusal and failed to name the screen. It correctly denied editing/publishing the executable. Raw requests/responses and cleanup evidence are retained in Orivyn-local-agent-smoke/knowledge-current. The server was stopped. This is a semantic failure, not a passing model capability claim.

To provide a reliable user path independent of that model failure, direct typed requests such as “Inspect Orivyn source” now offer the existing reviewed navigation button to the source screen. This does not connect, extract credentials, send the draft, inspect automatically or grant permissions. Two actual Swift suggestion tests verify direct requests and rejection of quoted/discussion/negated/unrelated requests. It is explicitly deterministic UI navigation, not autonomous tool reasoning. RootView routing is syntax-parsed only; actual iPhone navigation remains unverified.

254 Foundation XCTest cases,134 Python checks and70 agentJS tests pass. Together with26 separate SQLite cases,280 distinct Swift XCTest cases have executed. Added prompt tests and existing native self-knowledge/inference tests to the manual Apple gate. No paid CI, IPA, public source or release/catalog changes.
