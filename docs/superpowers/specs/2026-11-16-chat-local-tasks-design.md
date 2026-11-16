# Chat-bound local tasks

User delegated design choices. Reuse the existing reviewed local planner rather than introducing a second agent or broadening automatic command parsing. A saved conversation can open a free-form local-task review from its draft; required search/message scope remains reviewed and Run explicit. Durable task cards in that conversation show reducer stage, recorded evidence and separately labeled unverified model answer. Resume is explicit and uses reducer recovery, never replays completed reads.

An atomic task envelope stores immutable origin conversation UUID with exact reducer bytes. Genuine legacy raw records remain accepted; malformed or incomplete envelopes fail closed, never rebind. Existing tasks/panel retained. Read-only local operations only; no plugin calls, installer, remote inference, private uploads, automatic send or completion claims. New chat-task mode requires an existing saved conversation; composer and attachments remain unchanged. Existing standalone tasks continue unchanged.

Capture conversation/provider revisions for preparing, approval and each Run. Conversation deletion, selection ABA, provider replacement/ABA or stale plan must invalidate operation before next model/tool call. Task cards are projections of durable task records, not duplicated chat messages; local result data is not silently supplied to a remote chat model. Failed initial atomic writes create neither a task nor a durable association. No dependency or CI change.

Alternative considered: embed task JSON in Conversation persistence. Rejected for duplicated authority/reducer state and larger migration. Automatic model tool dispatch rejected because prose/model output cannot grant operation scope.
