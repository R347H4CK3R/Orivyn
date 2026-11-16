# Typed plugin suggestion native presentation coverage

## Scope

Two new native UI tests exercise the real RootView suggestion card and existing
PluginToolCallView. A clearly labeled synthetic fixture provides model output
and an in-memory MCP server, not a real model, real network or tool execution.
It is not proof of actual-model tool selection quality.

The entire helper file and AppModel fixture entry are DEBUG-only. Root fixture
resolution requires both --uitesting and --root-view-fixture plugin-suggestion.
Each launch uses unique temporary SQLite, model, attachment, plugin and defaults
stores. No user data, credentials or private inputs are read or sent.

The fixture initializes and installs its synthetic catalog through PluginBroker.
Its scripted provider goes through ChatPluginProposalProvider's production
schema/parser, submit/preparedAssistant, exact conversation/provider/catalog
binding, and the normal private validate/publish methods. It never assigns
pending state directly or fabricates a completed approval. Current normal draft
eligibility is checked before entry. The production LocalAIProvider guard is
unchanged. Only the model output and MCP transport are substituted for this UI
fixture. Unexpected callTool increments a counter and throws, never simulating
success.

## New native tests (not run locally)

- testTypedSuggestionOpensExactReviewWithoutDispatchAndIsConsumed: opens the
  app-owned suggestion, inspects typed arguments and exact destination, prepares
  existing exact review, asserts Run is available but NEVER taps it, closes the
  sheet, checks draft preservation and consumed suggestion, and reads a fresh
  actor-backed zero-call counter.
- testConversationChangeInvalidatesTypedSuggestionWithoutDispatch: changes
  origin through the actual model selection action, requires bounded card
  disappearance, and verifies a freshly read zero-call counter.

Both retain screenshots and accessibility hierarchy. The existing fixture
availability test gains the new known mode, without adding a native test method.

## Local validation

Python source boundary regression passes; Swift frontend DEBUG and release
syntax checks and git diff checks pass. These do not prove SwiftUI typechecking,
presentation or simulator interaction. Parent-owned native CI must execute the
two tests; no CI or release is started by this change.

Full Python run: 278 tests, one existing skip and one failure in the unchanged
`test_assistant_identity.test_actionable_help_does_not_pretend_tools_ran` exact
wording assertion after base b54745a compacted ChatResponsePolicy. This branch
does not change that policy or test. The new fixture-boundary test passes.
Independent source review found no blocking issue. The cross-chat test covers
pending-card invalidation, not switching chats while a review sheet is open.
