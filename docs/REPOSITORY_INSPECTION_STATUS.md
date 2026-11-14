# Read-only repository inspection candidate

Source implemented locally, not native-compiled or authenticated on an actual iPhone. Not a completed self-repair feature.

Settings has an explicit private-source inspection screen. The user enters a fine-grained GitHub token with Contents: Read-only for R347H4CK3R/Orivyn. The actor holds it in memory only; the screen clears credentials/source on dismissal or background. No keychain, source files, logs, AI provider or plugin receives this token/source through this feature. HTTP transport disables persistent cookies/cache and refuses redirects. All requests are GET to the fixed api.github.com repository; raw server errors are not displayed.

The service resolves the default branch to a commit, then tree SHA, retains a bounded complete tree, and fetches a selected listed blob by SHA. It checks decoded byte length and Git blob SHA-1 framing/hash before presenting UTF-8 text. Oversized/binary/symlink/submodule entries are excluded or rejected; omitted entries are disclosed. Git's SHA-1 identity is not a replacement for HTTPS origin authentication. This does not validate source correctness.

Textual hints identify forced try, termination calls and TODO/FIXME markers, with explicit false-positive and no-proof wording. It does not execute repository instructions, send private source into a model, modify files, commit, build, sign or publish. No claim of autonomous diagnosis or bug repair is made.

12 native mock-transport tests cover endpoint/credential constraints, commit pinning, blob verification, source bounds, cancellation and redacted errors. These and one native static-hint test are authored, not run. Two portable structural guardrails pass but do not execute Swift. No token was requested or used during this implementation. Required next validation: native Swift6 build, mocked transport tests, explicit authorized GitHub authentication, real read/clear lifecycle and iPhone memory testing. No paid CI is authorized.
