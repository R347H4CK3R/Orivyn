# Connected-tool discovery from normal chat

The composer offers **Find a connected tool** when an installed connection is currently active with a reviewed live catalog, a selected model is available, a bounded nonempty draft exists, and resource/foreground admission permits work. It is not a search for plugins to install and does not connect an inactive server.

The disclosure is visible beside the action before the tap. Tapping sends only the captured draft text and live tool schemas to the selected model to produce one schema-validated proposal. With an online model, that provider receives this text. Existing attachments, history, memory, location and plugin credentials are not automatically included. The draft and attachments stay in the composer. Nothing is submitted by typing or ordinary chat Send. The existing tool proposal screen opens directly, with one automatic proposal attempt after this explicit action; retries remain explicit.

A proposal is not authority to execute. The user must still inspect the exact tool arguments, select Review, and explicitly Run the reviewed call. Existing server-reported result handoff remains an explicit append-to-draft action, never automatic Send or additional tool execution. Unsupported proposals remain unsupported without fabricated success.

Conversation revision, provider revision, connection identity and catalog revision are captured at entry. Provider/conversation switch-away-and-back and provider replacement invalidate the original request. These origins are retained in SwiftUI State rather than recalculated on redraw. Stale checks run before model inference, when its result returns, when preparing the tool review and before dispatching Run. Originating contexts continue through the result handoff. The manual plugin path remains available and does not auto-generate a proposal when opened.

## Scope and verification

This is incremental conversational tool discovery, not unrestricted autonomous remote execution, background prompt scanning, universal plugin installation or parity with ChatGPT.

Three new portable tests cover bounded goals, every stale identity and the interaction between malicious remote-result text appended to a local-search draft and automatic local-read classification. The complete Foundation suite passed 540 tests with the existing Linux-only redirect-fixture exclusion. One new native AppModel test covers provider switch-away/back and replacement revisions; native SwiftUI runtime/typecheck and actual connected-provider behavior remain unverified. Swift syntax parsing and git diff checks passed. No CI, release or publication was dispatched.

The full Python suite again ran 271 tests with the same four failures/four errors/one skip documented in `plugin-result-handoff.md`, previously reproduced on untouched baseline. They concern generated guest assets, existing native gate fixtures, attachment fitting and backup UI source contracts; no test was disabled or weakened here.
