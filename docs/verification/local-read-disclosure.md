# Normal-chat local-read scope caption

Adds the requested scope caption only when `AppModel.automaticLocalChatReadsAvailable` is true:

> On-device assistant may read saved memories, app info and installed models. Read receipts appear in chat.

Accessibility identifier: `composer.localReads.notice`. This is disclosure, not an additional confirmation or execution button. It does not promise installed plugins, remote tools or file access. Eligibility and actual read execution remain owned by the separate automatic-local-chat implementation; this change must be integrated with that computed property before native compilation.

The source-contract test failed before implementation and passed afterward. Full Python suite: 272 tests passed with one existing skip. Swift frontend syntax parsing and diff checks pass. Native layout/accessibility and combined AppModel typechecking are not verified here. No CI dispatch or publication.

Follow-up: the direct/no-model execution caption now uses `model.currentDirectLocalReadContract`, the same origin-aware dispatcher contract, instead of independently parsing raw composer text. Imported/shared/plugin text must not receive this claim unless dispatcher eligibility permits it. Manual nonexecuting task review remains available. A second source-contract regression failed before this change and passed afterward. Follow-up full Python suite: 273 tests, one existing skip, no failures. Behavioral origin gating remains tested by the companion AppModel implementation.
