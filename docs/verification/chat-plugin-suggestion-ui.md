# On-device connected-tool proposal UI

Baseline: cebfc53. Companion implementation depends on AppModel APIs from the separate proposal implementation: pendingPluginProposal, pluginProposalReviewRoute(id:), dismissPluginProposal(id:), and ChatPluginReviewRoute.

An app-owned metadata card says “Suggested call · not executed”. The card is not parsed from assistant prose. Review validates the live route through AppModel, serializes bounded arguments, then consumes only the matching pending suggestion and presents an immutable route directly in existing PluginToolCallView. Consumption prevents a completed call from later reappearing as an unexecuted suggestion. Closing review requires a fresh suggestion; it does not send anything.

PluginToolCallView still requires explicit exact-call review followed by Run. No remote drafting view, broker execution call, automatic Send, new permission grant or connection installation is added. Conversation/provider/catalog/connection changes invalidate presentation; generation/model preparation also invalidates it. Covering-sheet host disappearance is not used as a teardown signal. The existing tool view handles its own lifecycle and uncertain execution outcomes.

Three source-contract tests were observed failing before their respective changes and passing afterward. Full Python suite: 276 tests, one existing skip, no failures. Swift frontend syntax and diff checks pass. Source tests are not native rendering, typechecking or execution proof. No synthetic model-result injection or private data is added for UI tests.

Native open → exact review → Run/cancel → close behavior, modal lifecycle and combined AppModel APIs still require native verification. No CI, IPA or release was dispatched.
